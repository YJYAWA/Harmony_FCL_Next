/**
 * Jar Executor 服务
 * 移植自: FCL/game/JarExecutorHelper + JarExecutorLauncher
 *
 * 功能: 执行任意 JAR 文件 (模组安装器、工具等)
 * 通过 JVM 运行时运行 JAR, 捕获输出
 */
import { FileUtils } from '../core/util/FileUtils';
import { SettingsManager } from '../core/SettingsManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-JarExecutor';

/** JAR 执行配置 */
export interface JarExecutorConfig {
  /** JAR 文件路径 */
  jarPath: string;
  /** JVM 参数 */
  jvmArgs: string[];
  /** 程序参数 */
  programArgs: string[];
  /** 工作目录 */
  workingDir?: string;
  /** Java 运行时路径 */
  javaPath?: string;
  /** 最大内存 (MB) */
  maxMemory?: number;
}

/** JAR 执行结果 */
export interface JarExecutorResult {
  success: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
  executionTime: number;
}

/** 执行进度回调 */
export interface JarExecutorCallbacks {
  onOutput?: (line: string) => void;
  onError?: (line: string) => void;
  onComplete?: (result: JarExecutorResult) => void;
}

/**
 * JAR 执行器服务
 * 支持:
 * - Forge/NeoForge 安装器
 * - Fabric 安装器
 * - OptiFine 安装器
 * - 自定义 JAR 工具
 */
export class JarExecutorService {
  private static instance: JarExecutorService | null = null;

  private constructor() {
  }

  static getInstance(): JarExecutorService {
    if (!JarExecutorService.instance) {
      JarExecutorService.instance = new JarExecutorService();
    }
    return JarExecutorService.instance;
  }

  /**
   * 执行 JAR 文件
   */
  async execute(config: JarExecutorConfig, callbacks?: JarExecutorCallbacks): Promise<JarExecutorResult> {
    const startTime = Date.now();

    hilog.info(0x0000, TAG, `Executing JAR: ${config.jarPath}`);

    try {
      // 验证 JAR 文件
      if (!FileUtils.exists(config.jarPath)) {
        throw new Error(`JAR file not found: ${config.jarPath}`);
      }

      // 构建 JVM 命令行
      const settings = SettingsManager.getInstance();
      const javaPath = config.javaPath ?? settings.get('javaPath') ?? 'java';
      const maxMem = config.maxMemory ?? 1024;

      const command: string[] = [
        javaPath,
        `-Xmx${maxMem}M`,
        ...config.jvmArgs,
        '-jar', config.jarPath,
        ...config.programArgs
      ];

      hilog.info(0x0000, TAG, `Command: ${command.join(' ')}`);

      // ===== NAPI 调用点 =====
      // TODO: 通过 NAPI 启动 JVM 子进程执行 JAR
      // 类似 GameLauncherService 的做法
      //
      // const pid = native.executeJar(jarPath, jvmArgs, programArgs);
      // const exitCode = await native.waitForProcess(pid);
      //
      // 当前为骨架实现, 模拟输出
      // =======================

      if (callbacks?.onOutput) {
        callbacks.onOutput(`[FCL] Executing: ${command.join(' ')}`);
        callbacks.onOutput(`[FCL] Java: ${javaPath}`);
      }

      // 模拟执行过程
      const mockOutput = [
        'Starting JAR execution...',
        'Loading libraries...',
        'Processing...',
        'Installation complete!'
      ];

      for (const line of mockOutput) {
        await this.delay(500);
        if (callbacks?.onOutput) {
          callbacks.onOutput(line);
        }
      }

      const result: JarExecutorResult = {
        success: true,
        exitCode: 0,
        stdout: mockOutput.join('\n'),
        stderr: '',
        executionTime: Date.now() - startTime
      };

      if (callbacks?.onComplete) {
        callbacks.onComplete(result);
      }

      return result;

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      hilog.error(0x0000, TAG, `JAR execution failed: ${errorMsg}`);

      const result: JarExecutorResult = {
        success: false,
        exitCode: 1,
        stdout: '',
        stderr: errorMsg,
        executionTime: Date.now() - startTime
      };

      if (callbacks?.onError) {
        callbacks.onError(errorMsg);
      }

      if (callbacks?.onComplete) {
        callbacks.onComplete(result);
      }

      return result;
    }
  }

  /**
   * 执行 Forge 安装器
   */
  async installForge(installerPath: string, minecraftDir: string,
    callbacks?: JarExecutorCallbacks): Promise<JarExecutorResult> {
    return this.execute({
      jarPath: installerPath,
      jvmArgs: ['-Djava.awt.headless=true'],
      programArgs: ['--installClient', minecraftDir],
      workingDir: minecraftDir
    }, callbacks);
  }

  /**
   * 执行 Fabric 安装器
   */
  async installFabric(installerPath: string, minecraftDir: string,
    mcVersion: string, loaderVersion: string,
    callbacks?: JarExecutorCallbacks): Promise<JarExecutorResult> {
    return this.execute({
      jarPath: installerPath,
      jvmArgs: [],
      programArgs: [
        'client',
        '-dir', minecraftDir,
        '-mcversion', mcVersion,
        '-loader', loaderVersion
      ],
      workingDir: minecraftDir
    }, callbacks);
  }

  /**
   * 执行 OptiFine 安装器
   */
  async installOptiFine(installerPath: string, minecraftDir: string,
    callbacks?: JarExecutorCallbacks): Promise<JarExecutorResult> {
    return this.execute({
      jarPath: installerPath,
      jvmArgs: [],
      programArgs: [minecraftDir],
      workingDir: minecraftDir
    }, callbacks);
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
