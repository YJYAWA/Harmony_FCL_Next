/**
 * Jar Executor 服务
 * 移植自: FCL/game/JarExecutorHelper + JarExecutorLauncher
 *
 * 功能: 执行任意 JAR 文件 (模组安装器、工具等)
 * 通过 JVM 运行时运行 JAR, 捕获输出
 */
import { FileUtils } from '../core/util/FileUtils';
import { SettingsManager } from '../core/SettingsManager';
import { AppContext } from '../common/AppContext';
import { hilog } from '@kit.PerformanceAnalysisKit';
import native from 'libfcl_native.so';

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
   *
   * 通过 NAPI 调用原生层（libfcl_native.so）：fork 子进程 → 子进程经
   * jvmInit（含 OHOS 信号链桥）嵌入 JVM → 从 jar manifest 读取 Main-Class
   * → 调用 main()。子进程 stdout/stderr 重定向到日志文件。
   */
  async execute(config: JarExecutorConfig, callbacks?: JarExecutorCallbacks): Promise<JarExecutorResult> {
    const startTime = Date.now();

    hilog.info(0x0000, TAG, `Executing JAR: ${config.jarPath}`);

    try {
      // 验证 JAR 文件
      if (!FileUtils.exists(config.jarPath)) {
        throw new Error(`JAR file not found: ${config.jarPath}`);
      }

      // Java 运行时（<jdk>/bin/java 形式）
      const settings = SettingsManager.getInstance();
      const javaPath = config.javaPath ?? settings.get('javaPath') ?? '';
      const maxMem = config.maxMemory ?? 1024;

      if (!javaPath || !FileUtils.exists(javaPath)) {
        throw new Error('Java runtime not found. Please download JDK first.');
      }

      // 推导 JDK 根目录：<jdk>/bin/java → <jdk>
      const binIndex = javaPath.lastIndexOf('/bin/');
      if (binIndex <= 0) {
        throw new Error(`Cannot derive JDK directory from javaPath: ${javaPath}`);
      }
      const jdkDir = javaPath.substring(0, binIndex);

      const workDir = config.workingDir ?? AppContext.filesDir;
      const logFile = `${workDir}/installer_output.log`;
      const jvmArgs: string[] = [`-Xmx${maxMem}M`, ...config.jvmArgs];

      if (callbacks?.onOutput) {
        callbacks.onOutput(`[FCL] Executing: ${config.jarPath}`);
        callbacks.onOutput(`[FCL] JDK: ${jdkDir} (xmx=${maxMem}M)`);
      }

      // ===== NAPI 调用：fork 子进程执行安装器 =====
      const exitCode = await native.executeJar(
        AppContext.filesDir,
        jdkDir,
        config.jarPath,
        jvmArgs,
        config.programArgs,
        workDir,
        logFile,
        maxMem
      );

      // 安装器输出已由 native 侧重定向到 logFile，读回传给回调
      const output = FileUtils.readText(logFile) ?? '';
      const outputLines = output.split('\n');
      for (const line of outputLines) {
        if (line.trim().length > 0 && callbacks?.onOutput) {
          callbacks.onOutput(line);
        }
      }

      const result: JarExecutorResult = {
        success: exitCode === 0,
        exitCode: exitCode,
        stdout: output,
        stderr: exitCode === 0 ? '' : `Installer exited with code ${exitCode} (native status: ${native.getStatus()})`,
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
}
