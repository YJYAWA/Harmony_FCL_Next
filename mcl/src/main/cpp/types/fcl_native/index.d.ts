/**
 * fcl_native — FCL-HarmonyOS 原生桥接层类型声明
 *
 * 实现见 mcl/src/main/cpp/napi/fcl_napi.cpp
 */
export const checkJitAvailable: () => boolean;

/**
 * 进程内嵌入启动 JVM 并调用主类 main()。
 * @param filesDir 应用沙箱 filesDir
 * @param jdkDir   JDK 根目录（如 filesDir/jdk/17）
 * @param argv     完整 java 命令行（buildLaunchCommand 的输出）
 * @param renderer 渲染器：'mobileglues'(默认) / 'mobilegl'(DirectVulkan, MC 26.3+) / 'gl4es' / 'auto'
 * @returns Promise，游戏 main() 返回后 resolve 退出码（0 成功 / 负数失败码）
 */
export const launchJVM: (filesDir: string, jdkDir: string, argv: Array<string>, renderer?: string) => Promise<number>;

/**
 * fork 子进程运行 `java -jar <jarPath>`（Forge/Fabric/OptiFine 安装器）。
 * @returns Promise，子进程退出码
 */
export const executeJar: (filesDir: string, jdkDir: string, jarPath: string,
  jvmArgs: Array<string>, programArgs: Array<string>,
  workDir: string, logFile: string, xmxMb: number) => Promise<number>;

/** 经 JNI System.exit(0) 请求游戏退出 */
export const stopGame: () => void;

/** 最近一次 JVM 操作的状态/错误描述 */
export const getStatus: () => string;

/** JVM 运行时身份：0=Fresh 1=创建中/已创建 2=就绪 3=fork 保留中 */
export const getRuntimeState: () => number;

/** 游戏是否正在运行 */
export const isGameRunning: () => boolean;

/** 输入注入（ring buffer，Phase 2 GLFW 兼容层消费） */
export const sendKeyEvent: (keyCode: number, action: number) => void;
export const sendMouseButton: (button: number, action: number) => void;
export const sendCursorPos: (x: number, y: number) => void;
/** 取走全部已排队的输入事件，扁平化为 [type, key, action, x, y, ...] */
export const drainInputEvents: () => Array<number>;
