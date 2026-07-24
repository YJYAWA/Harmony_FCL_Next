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
import { process } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LaunchConfig, GameProcessState } from '../core/game/GameTypes';
import { FileUtils } from '../core/util/FileUtils';
import { Constants } from '../core/util/Constants';
import { SettingsManager } from '../core/SettingsManager';

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
    isRunning: false
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
    return { ...this.processState, logLines: [...this.logLines] };
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
   * 注意: 当前版本通过 NAPI 调用原生 JVM 启动器
   * 完整实现需要:
   * 1. 编译 OpenJDK for HarmonyOS (参考 AMCL 的 JDK releases)
   * 2. 实现 NAPI 桥接层 (对应 FCLauncher 的 JNI 代码)
   * 3. 通过 posix_spawn 启动 JVM 进程
   *
   * 当前为骨架实现, 展示了完整的启动流程
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
      // 验证 Java 运行时
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

      // 构建命令行
      const commandArgs = this.buildLaunchCommand(config);
      hilog.info(0x0000, TAG, `Command: ${commandArgs.join(' ')}`);

      // ============ NAPI 调用点 ============
      // TODO: 通过 NAPI 调用原生 JVM 启动器
      // 参考: FCLauncher/jni/jre_launcher.c
      // HarmonyOS 使用 posix_spawn 或 fork+exec
      //
      // import native from 'libfcl_native.so';
      // const pid = native.launchJVM(commandArgs, envVars);
      //
      // 当前为占位实现
      // ===================================

      this.processState.isRunning = true;
      this.processState.startTime = Date.now();
      this.processState.pid = 0; // 将由 NAPI 返回真实 PID

      this.logLine(`[FCL] Launching Minecraft ${config.version}...`);
      this.logLine(`[FCL] Java: ${config.javaPath}`);
      this.logLine(`[FCL] Args: ${commandArgs.slice(0, 10).join(' ')}...`);

      return { success: true, pid: this.processState.pid };

    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Launch failed: ${error.message}`);
      this.processState.isRunning = false;
      return { success: false, error: error.message };
    }
  }

  /**
   * 停止游戏进程
   */
  async stopGame(): Promise<void> {
    if (!this.processState.isRunning) {
      return;
    }

    hilog.info(0x0000, TAG, 'Stopping Minecraft...');

    try {
      // NAPI 调用: 向 JVM 发送 SIGTERM
      // native.stopJVM(this.processState.pid);
      this.processState.isRunning = false;
      this.processState.exitCode = 0;
      this.logLine('[FCL] Game stopped.');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Stop failed: ${error.message}`);
    }
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
