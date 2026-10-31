/**
 * Minecraft 游戏启动服务
 * 负责 JVM 进程管理和游戏启动参数构建
 *
 * 核心职责:
 * 1. 构建 Minecraft 启动命令行
 * 2. 通过 NAPI 启动 OpenJDK/JVM 进程
 * 3. 监控游戏进程状态
 * 4. 处理游戏日志输出
 *
 * 参考: AMCL 的 JVM 启动方案
 * - 使用预编译的 OpenJDK for HarmonyOS NEXT (musl, aarch64)
 * - 需要 ALLOW_WRITABLE_CODE_MEMORY ACL
 * - 通过 XComponent 提供 OpenGL ES 渲染表面
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LaunchConfig, GameProcessState } from '../core/game/GameTypes';
import { FileUtils } from '../core/util/FileUtils';
import { Constants } from '../core/util/Constants';
import { SettingsManager } from '../core/SettingsManager';
import { AppContext } from '../common/AppContext';
import native from 'libfcl_native.so';

const TAG = 'FCL-GameLauncher';

/** 游戏启动结果 */
export interface LaunchResult {
  success: boolean;
  pid?: number;
  error?: string;
}

/** 游戏进程事件回调 */
export interface GameProcessCallbacks {
  onOutput?: (line: string) => void;
  onExit?: (exitCode: number) => void;
  onError?: (error: string) => void;
}

/**
 * 游戏启动器服务
 */
export class GameLauncherService {
  private static instance: GameLauncherService | null = null;
  private processState: GameProcessState = {
    pid: 0,
    isRunning: false,
    logLines: []
  };
  private callbacks: GameProcessCallbacks = {};
  private logLines: string[] = [];

  private constructor() {
  }

  static getInstance(): GameLauncherService {
    if (!GameLauncherService.instance) {
      GameLauncherService.instance = new GameLauncherService();
    }
    return GameLauncherService.instance;
  }

  get state(): GameProcessState {
    return {
      pid: this.processState.pid,
      isRunning: this.processState.isRunning,
      exitCode: this.processState.exitCode,
      startTime: this.processState.startTime,
      logLines: [...this.logLines]
    };
  }

  get isRunning(): boolean {
    return this.processState.isRunning;
  }

  /** 设置回调 */
  setCallbacks(callbacks: GameProcessCallbacks): void {
    this.callbacks = callbacks;
  }

  /**
   * 构建 Minecraft 启动命令行
   * 对应 FCLauncher 的启动参数组装逻辑
   */
  buildLaunchCommand(config: LaunchConfig): string[] {
    const args: string[] = [];

    // Java 可执行文件路径
    args.push(config.javaPath);

    // JVM 参数
    // 内存设置
    args.push(`-Xms${config.minMemory}M`);
    args.push(`-Xmx${config.maxMemory}M`);

    // HarmonyOS 特有: 开启可写代码内存 (JIT 必需)
    // 此 ACL 在 module.json5 中已声明
    args.push('-XX:+AllowWritableCodeMemory');

    // 默认 GC 参数
    Constants.DEFAULT_JVM_ARGS.forEach(arg => args.push(arg));

    // 额外 JVM 参数
    config.extraJVMArgs.forEach(arg => {
      if (arg.trim().length > 0) {
        args.push(arg);
      }
    });

    // 库路径
    const nativesDir = `${config.gameDir}/natives`;
    args.push(`-Djava.library.path=${nativesDir}`);

    // Minecraft 客户端参数
    const classpath = this.buildClasspath(config);
    args.push('-cp');
    args.push(classpath);

    // 主类
    args.push(this.getMainClass(config));

    // 游戏参数
    args.push(`--username`);
    args.push(config.authUsername);
    args.push(`--uuid`);
    args.push(config.authUUID);
    args.push(`--accessToken`);
    args.push(config.authAccessToken);
    args.push(`--version`);
    args.push(config.version);
    args.push(`--gameDir`);
    args.push(config.gameDir);
    args.push(`--assetsDir`);
    args.push(`${config.gameDir}/assets`);

    if (config.serverAddress) {
      args.push(`--server`);
      args.push(config.serverAddress);
    }

    if (config.demo) {
      args.push('--demo');
    }

    if (config.fullscreen) {
      args.push('--fullscreen');
    }

    args.push(`--width`);
    args.push(config.windowWidth.toString());
    args.push(`--height`);
    args.push(config.windowHeight.toString());

    return args;
  }

  /**
   * 构建 classpath
   */
  private buildClasspath(config: LaunchConfig): string {
    const librariesDir = `${config.gameDir}/libraries`;
    const versionJar = `${config.gameDir}/versions/${config.version}/${config.version}.jar`;

    const parts: string[] = [versionJar];

    // 收集所有依赖 jar
    if (FileUtils.exists(librariesDir)) {
      this.collectJars(librariesDir, parts);
    }

    return parts.join(':');
  }

  /** 递归收集所有 .jar 文件 */
  private collectJars(dir: string, result: string[]): void {
    try {
      const files = FileUtils.listFiles(dir);
      files.forEach(file => {
        const fullPath = `${dir}/${file}`;
        if (FileUtils.isDirectory(fullPath)) {
          this.collectJars(fullPath, result);
        } else if (file.endsWith('.jar')) {
          result.push(fullPath);
        }
      });
    } catch {
      // 忽略收集错误
    }
  }

  /** 获取主类名 */
  private getMainClass(config: LaunchConfig): string {
    // 从版本 JSON 中读取主类
    const versionJSON = FileUtils.readJSON<Record<string, Object>>(
      `${config.gameDir}/versions/${config.version}/${config.version}.json`
    );
    if (versionJSON && versionJSON['mainClass']) {
      return versionJSON['mainClass'] as string;
    }
    return 'net.minecraft.client.main.Main';
  }

  /**
   * 启动 Minecraft
   *
   * 通过 NAPI 调用原生 JVM 嵌入层（libfcl_native.so，移植自 AMCL 的方案）：
   * - OpenJDK for HarmonyOS 从 filesDir/jdk/<version>/ 经自研 ELF loader 加载
   * - 需要 ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY ACL 权限（JIT 必须）
   * - 游戏输出经 dup2 重定向到 <gameDir>/logs/latest.log，GameLogViewer 轮询读取
   */
  async launchGame(config: LaunchConfig): Promise<LaunchResult> {
    if (this.processState.isRunning) {
      return { success: false, error: 'Game is already running' };
    }

    hilog.info(0x0000, TAG, `Launching Minecraft ${config.version}`);
    hilog.info(0x0000, TAG, `Java: ${config.javaPath}`);
    hilog.info(0x0000, TAG, `Memory: ${config.minMemory}M-${config.maxMemory}M`);
    hilog.info(0x0000, TAG, `GameDir: ${config.gameDir}`);

    try {
      // 验证 Java 运行时（javaPath 形如 <filesDir>/jdk/17/bin/java）
      if (!config.javaPath || !FileUtils.exists(config.javaPath)) {
        return { success: false, error: 'Java runtime not found. Please download JDK first.' };
      }

      // 验证游戏文件
      const versionJar = `${config.gameDir}/versions/${config.version}/${config.version}.jar`;
      if (!FileUtils.exists(versionJar)) {
        return {
          success: false,
          error: `Version ${config.version} not installed. Please download it first.`
        };
      }

      // 前置检查：JIT（RWX mmap）权限
      if (!native.checkJitAvailable()) {
        return {
          success: false,
          error: 'JIT 权限不可用（RWX mmap 被拒绝）。请确认已申请 ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY 权限并使用 debug 签名。'
        };
      }

      // 构建命令行（native 侧解析 -Xmx / -cp / 主类 / --gameDir）
      const commandArgs = this.buildLaunchCommand(config);
      hilog.info(0x0000, TAG, `Command: ${commandArgs.slice(0, 8).join(' ')} ...`);

      // 推导 JDK 根目录：<jdk>/bin/java → <jdk>
      const jdkDir = this.deriveJdkDir(config.javaPath);
      if (!jdkDir) {
        return { success: false, error: `Cannot derive JDK directory from javaPath: ${config.javaPath}` };
      }

      const filesDir = AppContext.filesDir;

      this.processState.isRunning = true;
      this.processState.startTime = Date.now();
      this.processState.pid = -1; // 进程内嵌入模式无独立 PID

      this.logLine(`[FCL] Launching Minecraft ${config.version}...`);
      this.logLine(`[FCL] JDK: ${jdkDir}`);
      this.logLine(`[FCL] Memory: ${config.minMemory}M-${config.maxMemory}M`);

      // ============ NAPI 调用：进程内嵌入 JVM 并运行主类 ============
      // 阻塞语义由 Promise 承载：native 侧在 libuv 工作线程 jvmInit + jvmCallMain，
      // 游戏 main() 返回后 resolve 退出码。此 await 挂起直到游戏退出。
      // 渲染器选择（JavaManagePage 设置）激活 AMCL GraphicsPlan：
      //   mobileglues → GL→GLES 翻译；mobilegl → DirectVulkan（MC 26.3+）；gl4es → legacy
      const renderer = AppStorage.get<string>('fcl.renderer') ?? 'mobileglues';
      hilog.info(0x0000, TAG, `Renderer: ${renderer}`);
      const exitCode = await native.launchJVM(filesDir, jdkDir, commandArgs, renderer);

      this.processState.isRunning = false;
      this.processState.exitCode = exitCode;
      this.logLine(`[FCL] Game exited with code ${exitCode}.`);
      if (this.callbacks.onExit) {
        this.callbacks.onExit(exitCode);
      }

      return { success: exitCode === 0, pid: -1 };

    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Launch failed: ${error.message}`);
      this.processState.isRunning = false;
      if (this.callbacks.onError) {
        this.callbacks.onError(error.message ?? String(err));
      }
      return { success: false, error: error.message };
    }
  }

  /**
   * 从 java 路径推导 JDK 根目录
   * <filesDir>/jdk/17/bin/java → <filesDir>/jdk/17
   */
  private deriveJdkDir(javaPath: string): string {
    const binIndex = javaPath.lastIndexOf('/bin/');
    if (binIndex <= 0) {
      return '';
    }
    return javaPath.substring(0, binIndex);
  }

  /**
   * 停止游戏进程
   * 经 JNI System.exit(0) 触发 MC 的 shutdown hooks（保存世界等）
   */
  async stopGame(): Promise<void> {
    if (!this.processState.isRunning) {
      return;
    }

    hilog.info(0x0000, TAG, 'Stopping Minecraft...');

    try {
      native.stopGame();
      this.logLine('[FCL] Stop requested (System.exit via JNI).');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Stop failed: ${error.message}`);
    }
  }

  /** 检查游戏是否正在运行（native 侧实时状态） */
  isGameRunningNative(): boolean {
    return native.isGameRunning();
  }

  /** 获取 native 侧最近一次 JVM 操作的状态描述 */
  getNativeStatus(): string {
    return native.getStatus();
  }

  /** 添加日志行 */
  private logLine(line: string): void {
    this.logLines.push(line);
    // 保留最近 1000 行
    if (this.logLines.length > 1000) {
      this.logLines = this.logLines.slice(-500);
    }
    if (this.callbacks.onOutput) {
      this.callbacks.onOutput(line);
    }
  }
}
