/**
 * fcl_napi.cpp — FCL-HarmonyOS NAPI 桥接层（AMCL 栈适配版）
 *
 * 模块名 fcl_native（产物 libfcl_native.so），ArkTS 侧：
 *   import native from 'libfcl_native.so';
 *
 * 本 so 链接 libentry.so（DT_NEEDED）：加载时 AMCL 的 Init() 自动执行
 * （prepareMobileGluesRuntime / XComponent 回调注册 / 下载引擎注册），
 * 图形、输入、音频栈随之就绪。本文件只做两件事：
 *   1. 把 FCL 的 launchJVM/executeJar 命令行模型映射到 AMCL 的
 *      JVM 嵌入 API（jvmInit/jvmCallMain，AMCL GPL-3.0）；
 *   2. 提供输入 ring buffer 的 ArkTS 注入口（GLFW 兼容层的补充通道）。
 *
 * 类型声明见 ../types/fcl_native/index.d.ts。
 */

#include "napi/native_api.h"
#include "jvm/jvm_launcher.h"
#include "jvm/jni.h"
#include "napi/fcl_fork_jar.h"
#include "platform/graphics_plan.h"
#include "utils/amcl_log.h"

#include <hilog/log.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <atomic>

// EXTERN_C_START/END 兜底（不同 SDK 版本的 native_api.h 定义不一致）
#ifndef EXTERN_C_START
#define EXTERN_C_START extern "C" {
#endif
#ifndef EXTERN_C_END
#define EXTERN_C_END }
#endif

#undef LOG_TAG
#define LOG_TAG "FCL_NAPI"

// ============================================================
//  输入 ring buffer（PojavLauncher input_bridge_v3 模式的最小实现。
//  供 ArkTS 虚拟控件注入；AMCL 的 GLFW 层经由自己的 input runtime 消费
//  XComponent native 事件，本队列是 FCL ArkTS 控件事件的补充通道。）
// ============================================================
#define FCL_INPUT_QUEUE_SIZE 256
#define EVENT_TYPE_KEY 1
#define EVENT_TYPE_MOUSE 2
#define EVENT_TYPE_CURSOR 3

struct FclInputEvent {
    int32_t type;
    int32_t key;
    int32_t action;
    float x;
    float y;
};

static FclInputEvent g_inputQueue[FCL_INPUT_QUEUE_SIZE];
static std::atomic<int32_t> g_inputHead{0};
static std::atomic<int32_t> g_inputTail{0};

static void inputPush(int32_t type, int32_t key, int32_t action, float x, float y) {
    int32_t tail = g_inputTail.load(std::memory_order_relaxed);
    int32_t next = (tail + 1) % FCL_INPUT_QUEUE_SIZE;
    if (next == g_inputHead.load(std::memory_order_acquire)) {
        return; // 队列满，丢弃
    }
    g_inputQueue[tail] = {type, key, action, x, y};
    g_inputTail.store(next, std::memory_order_release);
}

static size_t inputDrain(int32_t* out, size_t outCap) {
    size_t count = 0;
    while (true) {
        int32_t head = g_inputHead.load(std::memory_order_relaxed);
        if (head == g_inputTail.load(std::memory_order_acquire)) break;
        if (count + 5 > outCap) break;
        const FclInputEvent& e = g_inputQueue[head];
        out[count++] = e.type;
        out[count++] = e.key;
        out[count++] = e.action;
        int32_t xi;
        float xf = e.x;
        memcpy(&xi, &xf, 4);
        out[count++] = xi;
        int32_t yi;
        float yf = e.y;
        memcpy(&yi, &yf, 4);
        out[count++] = yi;
        g_inputHead.store((head + 1) % FCL_INPUT_QUEUE_SIZE, std::memory_order_release);
    }
    return count;
}

// ============================================================
//  游戏启动状态
// ============================================================
static std::atomic<bool> g_gameRunning{false};

// ============================================================
//  argv 解析：从 FCL buildLaunchCommand 的 java 命令行提取结构化参数
// ============================================================
struct ParsedLaunch {
    std::string jdkDirFromArgv;             // 由 argv[0] java 路径推导（备用）
    std::string classpath;                  // -cp 值
    std::string gameDir;                    // --gameDir 值
    std::string mainClass;
    std::vector<std::string> jvmExtraArgs;  // 其余 JVM 参数（-XX:... -D...）
    std::vector<std::string> gameArgs;      // 主类之后的游戏参数
};

static ParsedLaunch parseLaunchArgv(const std::vector<std::string>& argv) {
    ParsedLaunch p;
    size_t i = 0;
    if (!argv.empty() && !argv[0].empty() && argv[0].find('/') != std::string::npos) {
        size_t binPos = argv[0].find("/bin/");
        if (binPos != std::string::npos) {
            p.jdkDirFromArgv = argv[0].substr(0, binPos);
        }
        i = 1;
    }
    bool mainClassFound = false;
    for (; i < argv.size(); i++) {
        const std::string& a = argv[i];
        if (mainClassFound) {
            p.gameArgs.push_back(a);
            continue;
        }
        if (a == "-cp" || a == "-classpath") {
            if (i + 1 < argv.size()) p.classpath = argv[++i];
            continue;
        }
        if (a == "--gameDir") {
            if (i + 1 < argv.size()) p.gameDir = argv[++i];
            continue;
        }
        if (a.rfind("-Xms", 0) == 0) {
            continue; // 初始堆交给 JVM 自动计算（AMCL 结论）
        }
        if (!a.empty() && a[0] == '-') {
            p.jvmExtraArgs.push_back(a);
            continue;
        }
        p.mainClass = a;
        mainClassFound = true;
    }
    return p;
}

/**
 * jdkDir → AMCL jdkVersion 参数。
 * AMCL jvmInit 约定 JDK 位于 <filesDir>/jdk/<version>/，jdkVersion 即 <version>。
 */
static std::string DeriveJdkVersion(const std::string& filesDir, const std::string& jdkDir) {
    const std::string prefix = filesDir + "/jdk/";
    if (jdkDir.rfind(prefix, 0) == 0 && jdkDir.size() > prefix.size()) {
        std::string rest = jdkDir.substr(prefix.size());
        while (!rest.empty() && rest.back() == '/') rest.pop_back();
        size_t slash = rest.find('/');
        return slash == std::string::npos ? rest : rest.substr(0, slash);
    }
    // 不在标准布局下：取 basename（如 .../jdk17 → "jdk17"）
    size_t slash = jdkDir.find_last_of('/');
    return slash == std::string::npos ? jdkDir : jdkDir.substr(slash + 1);
}

// ============================================================
//  异步工作：launchJVM / executeJar 共用的 Promise 模式
// ============================================================
struct LaunchWorkData {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    // 输入
    std::string filesDir;
    std::string jdkDir;
    std::string jarPath;
    std::string workDir;
    std::string logFile;
    int xmxMb = 1024;
    bool isJarMode = false;
    ParsedLaunch parsed;
    std::vector<std::string> jvmArgs;
    std::vector<std::string> programArgs;
    std::vector<std::string> argvAll;
    std::string renderer; // mobileglues(默认) / mobilegl / gl4es / auto
    // 输出
    int exitCode = 0;
};

/** 把游戏进程 stdout/stderr 持续重定向到游戏日志（GameLogViewer 轮询读取） */
static void RedirectGameOutput(const std::string& baseDir) {
    std::string logDir = baseDir + "/logs";
    mkdir(logDir.c_str(), 0755);
    std::string logFile = logDir + "/latest.log";
    int fd = open(logFile.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        close(fd);
    }
}

/** execute 阶段：在 libuv 工作线程运行（绝不在 ArkTS/JS 线程） */
static void LaunchExecute(napi_env env, void* data) {
    auto* w = static_cast<LaunchWorkData*>(data);

    if (w->isJarMode) {
        w->exitCode = fclForkRunJar(w->filesDir, w->jdkDir, w->jarPath,
                                    w->jvmArgs, w->programArgs,
                                    w->workDir, w->logFile, w->xmxMb);
        return;
    }

    // ---- 游戏模式：进程内嵌入 JVM（AMCL 方案）----
    const ParsedLaunch& p = w->parsed;

    if (g_gameRunning.load()) {
        w->exitCode = -20; // 已有游戏在运行
        return;
    }
    g_gameRunning.store(true);

    if (p.mainClass.empty()) {
        w->exitCode = -21;
        g_gameRunning.store(false);
        return;
    }

    // AMCL jvmInit 读取的环境变量
    const std::string gameDir = p.gameDir.empty() ? w->filesDir : p.gameDir;
    setenv("AMCL_GAME_DIR", gameDir.c_str(), 1);

    // 配置 JVM（AMCL API）
    jvmSetClasspath(p.classpath.c_str());
    // Xmx 经用户 extraArgs 透传（FCL buildLaunchCommand 生成 -Xmx...M）
    jvmSetExtraArgsList(p.jvmExtraArgs);

    // 派生 JDK：优先 ArkTS 显式传入，其次从 argv[0] 推导
    std::string jdkDir = w->jdkDir.empty() ? p.jdkDirFromArgv : w->jdkDir;
    if (jdkDir.empty()) {
        w->exitCode = -22;
        g_gameRunning.store(false);
        return;
    }
    std::string jdkVersion = DeriveJdkVersion(w->filesDir, jdkDir);

    // ============================================================
    //  渲染器选择 → AMCL GraphicsPlan 激活
    //  （在 jvmInit 之前激活，jvm_launcher 会注入 -Damcl.graphics.profile，
    //   图形后端会话据此选择 EGL/MobileGlues 或 MobileGL(DirectVulkan) 提供者。）
    //  wire 协议与 AMCL GraphicsBackendPlan.serializeGraphicsPlan 完全一致：
    //    v1（7 字段）：v;profile;api;window;route;transport;strict
    //    v2（12 字段）：v;profile;api;window;route;transport;strict;policy;game;slot;admission;requirement
    // ============================================================
    {
        std::string wire;
        if (w->renderer == "mobilegl") {
            // MC 26.3+：MobileGL DirectVulkan（SDL3 窗口提供者 + 26.3 保守审计基线）
            wire = "v=v2;profile=minecraft-vulkan;api=VULKAN;window=SDL3;route=minecraft-vulkan"
                   ";transport=YES;strict=0;policy=ALLOW;game=VULKAN;slot=LWJGL3"
                   ";admission=VALIDATION;requirement=minecraft-26.3-sdl-vulkan-conservative-v1";
        } else if (w->renderer == "gl4es") {
            wire = "v=v1;profile=gl4es;api=OPENGL;window=GLFW;route=gl4es;transport=UNKNOWN;strict=0";
        } else {
            // 默认与 'mobileglues'/'auto'：MobileGlues（AMCL 实测基线）
            wire = "v=v1;profile=mobileglues;api=OPENGL;window=GLFW;route=mobileglues;transport=UNKNOWN;strict=0";
        }
        amcl::graphics::GraphicsPlan plan;
        std::string planError;
        if (amcl::graphics::ParseGraphicsPlan(wire, plan, planError) &&
            amcl::graphics::ActivateGraphicsPlan(plan, planError)) {
            AMCL_LOG_I(LOG_TAG, "graphics plan activated: renderer=%{public}s profile=%{public}s",
                       w->renderer.c_str(), plan.profile.c_str());
        } else {
            // 计划被拒不阻断启动——回到 AMCL 无计划默认行为，但要把原因留在日志里
            AMCL_LOG_E(LOG_TAG, "graphics plan rejected (%{public}s): renderer=%{public}s wire=%{public}s",
                       planError.c_str(), w->renderer.c_str(), wire.c_str());
        }
    }

    AMCL_LOG_I(LOG_TAG, "launchJVM: jdk=%{public}s mainClass=%{public}s cp=%{public}zu chars",
               jdkVersion.c_str(), p.mainClass.c_str(), p.classpath.size());

    // 初始化 JVM（一次性；AMCL 语义：失败后本进程不能再建，需重启应用）
    int initRc = jvmInit(w->filesDir.c_str(), jdkVersion.c_str());
    if (initRc != 0) {
        AMCL_LOG_E(LOG_TAG, "jvmInit failed rc=%{public}d: %{public}s", initRc, jvmGetStatus());
        w->exitCode = initRc;
        g_gameRunning.store(false);
        return;
    }

    // 游戏运行期输出重定向到游戏日志
    RedirectGameOutput(gameDir);

    // 调用主类 main()——阻塞到游戏退出
    std::vector<const char*> gameArgv;
    gameArgv.reserve(p.gameArgs.size());
    for (const auto& a : p.gameArgs) gameArgv.push_back(a.c_str());
    int mainRc = jvmCallMain(p.mainClass.c_str(), (int)gameArgv.size(),
                             gameArgv.empty() ? nullptr : gameArgv.data());

    AMCL_LOG_I(LOG_TAG, "game main() returned %{public}d (status=%{public}s)", mainRc, jvmGetStatus());
    w->exitCode = mainRc;
    g_gameRunning.store(false);
}

/** complete 阶段：回到 JS 线程 resolve Promise */
static void LaunchComplete(napi_env env, napi_status status, void* data) {
    auto* w = static_cast<LaunchWorkData*>(data);
    napi_value exitCodeVal;
    napi_create_int32(env, w->exitCode, &exitCodeVal);
    if (w->deferred) {
        napi_resolve_deferred(env, w->deferred, exitCodeVal);
    }
    if (w->work) {
        napi_delete_async_work(env, w->work);
    }
    delete w;
}

// ============================================================
//  NAPI 导出实现
// ============================================================

static napi_value CheckJitAvailable(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_get_boolean(env, jvmCheckJitAvailable() == 1, &result);
    return result;
}

static std::string NapiGetString(napi_env env, napi_value v) {
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string out(len, '\0');
    if (len > 0) {
        napi_get_value_string_utf8(env, v, &out[0], len + 1, &len);
        out.resize(len);
    }
    return out;
}

static std::vector<std::string> NapiGetStringArray(napi_env env, napi_value arr) {
    std::vector<std::string> out;
    uint32_t len = 0;
    napi_get_array_length(env, arr, &len);
    out.reserve(len);
    for (uint32_t i = 0; i < len; i++) {
        napi_value item;
        if (napi_get_element(env, arr, i, &item) == napi_ok) {
            out.push_back(NapiGetString(env, item));
        }
    }
    return out;
}

/** launchJVM(filesDir: string, jdkDir: string, argv: string[], renderer?: string): Promise<number> */
static napi_value LaunchJVM(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 3) {
        napi_throw_error(env, nullptr, "launchJVM requires (filesDir, jdkDir, argv, [renderer])");
        return nullptr;
    }

    auto* w = new LaunchWorkData();
    w->isJarMode = false;
    w->filesDir = NapiGetString(env, argv[0]);
    w->jdkDir = NapiGetString(env, argv[1]);
    w->argvAll = NapiGetStringArray(env, argv[2]);
    if (argc >= 4 && argv[3] != nullptr) {
        w->renderer = NapiGetString(env, argv[3]);
    }
    w->parsed = parseLaunchArgv(w->argvAll);

    if (w->parsed.mainClass.empty()) {
        napi_throw_error(env, nullptr, "launchJVM: main class not found in argv");
        delete w;
        return nullptr;
    }

    napi_value promise;
    if (napi_create_promise(env, &w->deferred, &promise) != napi_ok) {
        delete w;
        return nullptr;
    }
    napi_value resource;
    napi_create_string_utf8(env, "fclLaunchJVM", NAPI_AUTO_LENGTH, &resource);
    napi_create_async_work(env, nullptr, resource, LaunchExecute, LaunchComplete, w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

/** executeJar(filesDir, jdkDir, jarPath, jvmArgs[], programArgs[], workDir, logFile, xmxMb): Promise<number> */
static napi_value ExecuteJar(napi_env env, napi_callback_info info) {
    size_t argc = 8;
    napi_value argv[8];
    for (size_t i = 0; i < 8; i++) argv[i] = nullptr;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 8) {
        napi_throw_error(env, nullptr,
            "executeJar requires (filesDir, jdkDir, jarPath, jvmArgs, programArgs, workDir, logFile, xmxMb)");
        return nullptr;
    }

    auto* w = new LaunchWorkData();
    w->isJarMode = true;
    w->filesDir = NapiGetString(env, argv[0]);
    w->jdkDir = NapiGetString(env, argv[1]);
    w->jarPath = NapiGetString(env, argv[2]);
    w->jvmArgs = NapiGetStringArray(env, argv[3]);
    w->programArgs = NapiGetStringArray(env, argv[4]);
    w->workDir = NapiGetString(env, argv[5]);
    w->logFile = NapiGetString(env, argv[6]);
    double xmx = 1024;
    napi_get_value_double(env, argv[7], &xmx);
    w->xmxMb = (int)xmx;

    napi_value promise;
    if (napi_create_promise(env, &w->deferred, &promise) != napi_ok) {
        delete w;
        return nullptr;
    }
    napi_value resource;
    napi_create_string_utf8(env, "fclExecuteJar", NAPI_AUTO_LENGTH, &resource);
    napi_create_async_work(env, nullptr, resource, LaunchExecute, LaunchComplete, w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

/** stopGame(): void — 经 JNI System.exit(0) 请求游戏退出 */
static napi_value StopGame(napi_env env, napi_callback_info info) {
    (void)info;
    void* vmPtr = jvmGetJavaVM();
    if (!vmPtr || !g_gameRunning.load()) {
        return nullptr;
    }
    JavaVM* vm = static_cast<JavaVM*>(vmPtr);
    JNIEnv* jEnv = nullptr;
    jint rc = vm->GetEnv((void**)&jEnv, JNI_VERSION_10);
    if (rc == JNI_EDETACHED) {
        vm->AttachCurrentThread((void**)&jEnv, nullptr);
    }
    if (!jEnv) return nullptr;

    jclass systemClass = jEnv->FindClass("java/lang/System");
    if (systemClass) {
        jmethodID exitMethod = jEnv->GetStaticMethodID(systemClass, "exit", "(I)V");
        if (exitMethod) {
            jEnv->CallStaticVoidMethod(systemClass, exitMethod, (jint)0);
        }
        jEnv->DeleteLocalRef(systemClass);
    }
    if (jEnv->ExceptionCheck()) jEnv->ExceptionClear();
    return nullptr;
}

static napi_value GetStatus(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_string_utf8(env, jvmGetStatus(), NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value GetRuntimeState(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_int32(env, jvmRuntimeState(), &result);
    return result;
}

static napi_value IsGameRunning(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_get_boolean(env, g_gameRunning.load(), &result);
    return result;
}

// ---- 输入注入 ----
static napi_value SendKeyEvent(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 2) return nullptr;
    double key = 0, action = 0;
    napi_get_value_double(env, argv[0], &key);
    napi_get_value_double(env, argv[1], &action);
    inputPush(EVENT_TYPE_KEY, (int32_t)key, (int32_t)action, 0.f, 0.f);
    return nullptr;
}

static napi_value SendMouseButton(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 2) return nullptr;
    double btn = 0, action = 0;
    napi_get_value_double(env, argv[0], &btn);
    napi_get_value_double(env, argv[1], &action);
    inputPush(EVENT_TYPE_MOUSE, (int32_t)btn, (int32_t)action, 0.f, 0.f);
    return nullptr;
}

static napi_value SendCursorPos(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 2) return nullptr;
    double x = 0, y = 0;
    napi_get_value_double(env, argv[0], &x);
    napi_get_value_double(env, argv[1], &y);
    inputPush(EVENT_TYPE_CURSOR, 0, 0, (float)x, (float)y);
    return nullptr;
}

/** drainInputEvents(): number[] — 扁平化 [type,key,action,x,y,...] */
static napi_value DrainInputEvents(napi_env env, napi_callback_info info) {
    (void)info;
    int32_t buf[FCL_INPUT_QUEUE_SIZE * 5];
    size_t count = inputDrain(buf, sizeof(buf) / sizeof(buf[0]));
    napi_value arr;
    napi_create_array_with_length(env, count, &arr);
    for (size_t i = 0; i < count; i++) {
        napi_value v;
        napi_create_int32(env, buf[i], &v);
        napi_set_element(env, arr, (uint32_t)i, v);
    }
    return arr;
}

// ============================================================
//  模块注册
// ============================================================
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "checkJitAvailable", nullptr, CheckJitAvailable, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "launchJVM", nullptr, LaunchJVM, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "executeJar", nullptr, ExecuteJar, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopGame", nullptr, StopGame, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getRuntimeState", nullptr, GetRuntimeState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isGameRunning", nullptr, IsGameRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendKeyEvent", nullptr, SendKeyEvent, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendMouseButton", nullptr, SendMouseButton, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendCursorPos", nullptr, SendCursorPos, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "drainInputEvents", nullptr, DrainInputEvents, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

// 官方模块注册宏：模块名 fcl_native → 产物 libfcl_native.so
NAPI_MODULE(fcl_native, Init)
