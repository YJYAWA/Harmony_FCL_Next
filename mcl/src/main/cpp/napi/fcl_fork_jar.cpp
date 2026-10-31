/**
 * fcl_fork_jar.cpp — FCL 安装器子进程封装
 *
 * ZIP manifest 解析为本文件自研（EOCD → 中央目录 → META-INF/MANIFEST.MF →
 * zlib raw inflate → 文本解析），JVM 子进程流程移植自 AMCL
 * (https://github.com/LZZLHY/amcl, GPL-3.0) 的 jvm/fork_run_java.cpp：
 * 原子保留 fork 窗口 → fork → 子进程验证 PID/重置 → 重定向 → chdir →
 * jvmSetForkChildMode(1) → jvmInit → jvmCallMain → _exit；父进程 waitpid。
 */

#include "fcl_fork_jar.h"
#include "jvm/jvm_launcher.h"
#include "utils/amcl_log.h"

#include <hilog/log.h>
#include <zlib.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <string>
#include <vector>
#include <cstdint>

#undef LOG_TAG
#define LOG_TAG "FCL_FORK_JAR"

// ============================================================
//  ZIP 读取（仅支持本机文件、有界解析）
// ============================================================
namespace {

uint16_t Le16(const uint8_t* b) { return (uint16_t)(b[0] | (b[1] << 8)); }
uint32_t Le32(const uint8_t* b) { return (uint32_t)(b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24)); }

bool ReadWholeFile(const std::string& path, std::vector<uint8_t>& out) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size <= 0 || size > (1L << 30)) { fclose(f); return false; }
    out.resize(static_cast<size_t>(size));
    size_t rd = fread(out.data(), 1, out.size(), f);
    fclose(f);
    return rd == out.size();
}

/** 定位 EOCD 并返回中央目录偏移/条目数 */
bool LocateCentralDir(const std::vector<uint8_t>& b, size_t& cdOffset, size_t& cdSize, size_t& entryCount) {
    if (b.size() < 22) return false;
    // EOCD 签名 0x06054b50，从尾部向前扫（最多注释区 64KB + 22）
    const size_t scanStart = b.size() >= 65557 ? b.size() - 65557 : 0;
    for (size_t i = b.size() - 22 + 1; i-- > scanStart;) {
        if (b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06) {
            entryCount = Le16(&b[i + 10]);
            cdSize = Le32(&b[i + 12]);
            cdOffset = Le32(&b[i + 16]);
            return true;
        }
    }
    return false;
}

/** 在中央目录中找目标条目，返回 (localHeaderOffset, compressedSize, method) */
bool FindZipEntry(const std::vector<uint8_t>& b, const std::string& name,
                  size_t& lhOffset, size_t& cSize, uint16_t& method) {
    size_t cdOffset, cdSize, entryCount;
    if (!LocateCentralDir(b, cdOffset, cdSize, entryCount)) return false;
    if (cdOffset + cdSize > b.size()) return false;
    size_t p = cdOffset;
    for (size_t n = 0; n < entryCount && p + 46 <= cdOffset + cdSize; n++) {
        if (!(b[p] == 0x50 && b[p + 1] == 0x4b && b[p + 2] == 0x01 && b[p + 3] == 0x02)) return false;
        uint16_t fnameLen = Le16(&b[p + 28]);
        uint16_t extraLen = Le16(&b[p + 30]);
        uint16_t commentLen = Le16(&b[p + 32]);
        cSize = Le32(&b[p + 20]);
        method = Le16(&b[p + 10]);
        size_t localOff = Le32(&b[p + 42]);
        if (p + 46 + fnameLen > cdOffset + cdSize) return false;
        std::string entryName(reinterpret_cast<const char*>(&b[p + 46]), fnameLen);
        if (entryName == name) {
            lhOffset = localOff;
            return true;
        }
        p += 46 + fnameLen + extraLen + commentLen;
    }
    return false;
}

/** 从本地文件头之后取数据并解压（deflate raw / stored） */
bool ExtractEntry(const std::vector<uint8_t>& b, size_t lhOffset, size_t cSize,
                  uint16_t method, std::vector<uint8_t>& out) {
    if (lhOffset + 30 > b.size()) return false;
    if (!(b[lhOffset] == 0x50 && b[lhOffset + 1] == 0x4b && b[lhOffset + 2] == 0x03 && b[lhOffset + 3] == 0x04)) return false;
    uint16_t fnameLen = Le16(&b[lhOffset + 26]);
    uint16_t extraLen = Le16(&b[lhOffset + 28]);
    size_t dataStart = lhOffset + 30 + fnameLen + extraLen;
    if (dataStart + cSize > b.size()) return false;

    if (method == 0) {
        out.assign(b.begin() + static_cast<long>(dataStart), b.begin() + static_cast<long>(dataStart + cSize));
        return true;
    }
    if (method != 8) return false;

    out.resize(cSize * 8 + 4096); // manifest 很小，给足余量
    z_stream state{};
    state.next_in = const_cast<uint8_t*>(&b[dataStart]);
    state.avail_in = static_cast<uInt>(cSize);
    state.next_out = out.data();
    state.avail_out = static_cast<uInt>(out.size());
    if (inflateInit2(&state, -MAX_WBITS) != Z_OK) return false;
    const int rc = inflate(&state, Z_FINISH);
    inflateEnd(&state);
    if (rc != Z_STREAM_END) return false;
    out.resize(state.total_out);
    return true;
}

} // namespace

std::string fclReadMainClassFromJar(const std::string& jarPath) {
    std::vector<uint8_t> bytes;
    if (!ReadWholeFile(jarPath, bytes)) return "";
    size_t lhOffset = 0, cSize = 0;
    uint16_t method = 0;
    if (!FindZipEntry(bytes, "META-INF/MANIFEST.MF", lhOffset, cSize, method)) return "";
    std::vector<uint8_t> manifest;
    if (!ExtractEntry(bytes, lhOffset, cSize, method, manifest)) return "";

    // 逻辑行解析（manifest 72 字节折行：续行以单个空格开头，属于上一条属性）
    std::string text(reinterpret_cast<const char*>(manifest.data()), manifest.size());
    std::string logical;      // 当前逻辑行（续行已拼接）
    std::string mainClass;
    auto commitLogical = [&]() {
        const std::string key = "Main-Class:";
        if (logical.rfind(key, 0) == 0) {
            size_t v = key.size();
            while (v < logical.size() && (logical[v] == ' ' || logical[v] == '\t')) v++;
            mainClass = logical.substr(v);
            while (!mainClass.empty() &&
                   (mainClass.back() == '\r' || mainClass.back() == ' ')) mainClass.pop_back();
        }
        logical.clear();
    };
    size_t start = 0;
    while (start <= text.size()) {
        // 找到一行（到 \n 或结尾）
        size_t end = text.find('\n', start);
        if (end == std::string::npos) end = text.size();
        std::string line = text.substr(start, end - start);
        if (!line.empty() && line[0] == ' ') {
            // 续行：去掉起始空格接回上一条逻辑行
            logical += line.substr(1);
        } else {
            commitLogical();
            logical = line;
        }
        if (end >= text.size()) break;
        start = end + 1;
    }
    commitLogical();
    return mainClass;
}

// ============================================================
//  子进程执行
// ============================================================
static void childMain(const std::string& filesDir, const std::string& jdkDir,
                      const std::string& jarPath,
                      const std::vector<std::string>& jvmArgs,
                      const std::vector<std::string>& programArgs,
                      const std::string& workDir, int xmxMb) {
    // 字体 / locale 环境（AMCL：钉 UTF-8 修中文路径）
    setenv("FONTCONFIG_PATH", filesDir.c_str(), 1);
    setenv("FONTCONFIG_FILE", (filesDir + "/fonts.conf").c_str(), 1);
    setenv("LC_ALL", "en_US.UTF-8", 1);
    setenv("LANG", "en_US.UTF-8", 1);
    // AMCL 的 jvmInit 读 AMCL_GAME_DIR 设 user.home/user.dir
    if (!workDir.empty()) {
        setenv("AMCL_GAME_DIR", workDir.c_str(), 1);
    }
    std::string jdkLib = jdkDir + "/lib";
    std::string ldPath = jdkLib + ":" + jdkLib + "/server";
    const char* oldLd = getenv("LD_LIBRARY_PATH");
    if (oldLd && oldLd[0]) { ldPath += ":"; ldPath += oldLd; }
    setenv("LD_LIBRARY_PATH", ldPath.c_str(), 1);

    // 预加载 fontconfig stub（AMCL：processor 防御性保留）
    std::string fcPath = jdkLib + "/libfontconfig.so.1";
    void* fcDl = dlopen(fcPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    fprintf(stdout, "[FCL_FORK] dlopen fontconfig: %s\n", fcDl ? "OK" : "fail");
    fflush(stdout);

    jvmSetForkChildMode(1);
    // 安装器专属：C1 编译（避免 BinaryPatcher 极慢）+ 小初始堆（AMCL 实测值）
    std::vector<std::string> extra;
    extra.push_back("-XX:TieredStopAtLevel=1");
    extra.push_back("-Xms128m");
    extra.push_back("-Dsun.java2d.fontpath=/system/fonts");
    for (const auto& a : jvmArgs) {
        if (!a.empty()) extra.push_back(a);
    }
    jvmSetExtraArgsList(extra);
    jvmSetXmx(xmxMb);
    // jar 本身由 URLClassLoader 回退加载（AMCL jvmCallMain 的 fork-child 回退）
    jvmSetClasspath(jarPath.c_str());

    fprintf(stdout, "[FCL_FORK] jvmInit... jdk=%s xmx=%dMB\n", jdkDir.c_str(), xmxMb);
    fflush(stdout);
    int initRc = jvmInit(filesDir.c_str(), jdkDir.c_str());
    if (initRc != 0) {
        fprintf(stderr, "[FCL_FORK] ERROR: jvmInit failed rc=%d: %s\n", initRc, jvmGetStatus());
        fflush(stderr);
        _exit(70);
    }

    std::string mainClass = fclReadMainClassFromJar(jarPath);
    if (mainClass.empty()) {
        fprintf(stderr, "[FCL_FORK] ERROR: Main-Class not found in %s\n", jarPath.c_str());
        fflush(stderr);
        _exit(72);
    }
    fprintf(stdout, "[FCL_FORK] Main-Class: %s, programArgs=%zu\n", mainClass.c_str(), programArgs.size());
    fflush(stdout);

    std::vector<const char*> argvPtrs;
    argvPtrs.reserve(programArgs.size());
    for (const auto& a : programArgs) argvPtrs.push_back(a.c_str());

    int mainRc = jvmCallMain(mainClass.c_str(), (int)argvPtrs.size(),
                             argvPtrs.empty() ? nullptr : argvPtrs.data());
    fprintf(stdout, "[FCL_FORK] jvmCallMain returned %d (status=%s)\n", mainRc, jvmGetStatus());
    fflush(stdout);

    // 不调 jvmDestroy（DestroyJavaVM 会等非守护线程可能挂起），直接 _exit
    _exit(mainRc == 0 ? 0 : 1);
}

int fclForkRunJar(const std::string& filesDir, const std::string& jdkDir,
                  const std::string& jarPath,
                  const std::vector<std::string>& jvmArgs,
                  const std::vector<std::string>& programArgs,
                  const std::string& workDir,
                  const std::string& logFile,
                  int xmxMb) {
    // AMCL 协议：原子保留从 Fresh 到 fork 返回的窗口
    const int reservation = jvmReserveForFork();
    if (reservation != 0) {
        AMCL_LOG_E(LOG_TAG, "fork rejected: reservation rc=%{public}d", reservation);
        return reservation == -8 ? -8 : -7;
    }
    AMCL_LOG_I(LOG_TAG, "fclForkRunJar: jar=%{public}s xmx=%{public}dMB", jarPath.c_str(), xmxMb);

    pid_t pid = fork();
    if (pid < 0) {
        const int forkError = errno;
        jvmReleaseForkReservation();
        AMCL_LOG_E(LOG_TAG, "fork() failed: %{public}s", strerror(forkError));
        return -1;
    }

    if (pid == 0) {
        // 子进程第一项运行时操作：验证保留态且 PID 已变化
        if (jvmResetForForkChild() != 0) {
            static const char error[] = "[FCL_FORK] invalid fork reservation; refusing inherited JVM state\n";
            write(STDERR_FILENO, error, sizeof(error) - 1);
            _exit(70);
        }
        if (!logFile.empty()) {
            int fd = open(logFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                close(fd);
            }
        }
        if (!workDir.empty()) {
            chdir(workDir.c_str());
            fprintf(stdout, "[FCL_FORK] chdir to %s\n", workDir.c_str());
        }
        childMain(filesDir, jdkDir, jarPath, jvmArgs, programArgs, workDir, xmxMb);
        _exit(99);
    }

    if (jvmReleaseForkReservation() != 0) {
        AMCL_LOG_E(LOG_TAG, "fork reservation release failed");
    }
    AMCL_LOG_I(LOG_TAG, "fclForkRunJar: child pid=%{public}d, waiting...", pid);

    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(pid, &status, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited < 0) {
        AMCL_LOG_E(LOG_TAG, "waitpid failed: %{public}s", strerror(errno));
        return -1;
    }

    int exitCode = -1;
    if (WIFEXITED(status)) {
        exitCode = WEXITSTATUS(status);
        AMCL_LOG_I(LOG_TAG, "child exited with code %{public}d", exitCode);
    } else if (WIFSIGNALED(status)) {
        AMCL_LOG_E(LOG_TAG, "child killed by signal %{public}d", WTERMSIG(status));
        exitCode = -128 + WTERMSIG(status);
    }
    return exitCode;
}
