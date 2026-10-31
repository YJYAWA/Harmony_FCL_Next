/**
 * Minecraft 游戏启动服务
 * 负责 JVM 进程管理和游戏启动参数构建
 *
 * 核心职责:
 * 1. 构建 Minecraft 启动命令行 (按版本 JSON 的 arguments/libraries)
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
import { LaunchConfig, GameProcessState, GameVersion, Library, LibraryDownloads,
  LibraryRule, VersionType, AssetIndex, JavaVersion, VersionDownloads } from '../core/game/GameTypes';
import { FileUtils } from '../core/util/FileUtils';
import { Constants } from '../core/util/Constants';
import { SettingsManager } from '../core/SettingsManager';
import { FmlConfigPatcher } from '../core/game/FmlConfigPatcher';
import { LibraryRules } from '../core/game/LibraryRules';
import { VersionArguments } from '../core/game/VersionArguments';
import { AppVersion } from '../core/util/AppVersion';
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
  private settingsManager: SettingsManager = SettingsManager.getInstance();
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
   *
   * 对应 FCLauncher 的启动参数组装逻辑：
   * java <JVM 参数> -cp <classpath> <mainClass> <游戏参数>
   *
   * @param config 启动配置
   * @param version 已解析（含继承链合并）的版本信息
   */
  buildLaunchCommand(config: LaunchConfig, version: GameVersion): string[] {
    const args: string[] = [];
    const mcDir = config.gameDir;
    // 实例目录（整合包隔离）：mods / config / saves 等写这里；未设置时就是 gameDir
    const instanceDir = config.instanceDir ?? config.gameDir;

    // 1. Java 可执行文件路径
    args.push(config.javaPath);

    // 2. JVM 参数
    // 内存设置
    args.push(`-Xms${config.minMemory}M`);
    args.push(`-Xmx${config.maxMemory}M`);

    // HarmonyOS 特有: 开启可写代码内存 (JIT 必需)
    // 此 ACL 在 module.json5 中已声明
    args.push('-XX:+AllowWritableCodeMemory');

    // 默认 GC 参数
    Constants.DEFAULT_JVM_ARGS.forEach(arg => args.push(arg));

    // 3. 版本 JSON 中声明的 JVM 参数 (arguments.jvm)
    //    过滤掉 -cp / -Djava.library.path / -XstartOnFirstThread (由启动器自行管理)
    const placeholders = this.buildPlaceholders(config, version, mcDir, instanceDir);
    const versionJvmArgs = VersionArguments.filterJvmArgs(version.arguments?.jvm ?? []);
    for (const raw of versionJvmArgs) {
      args.push(VersionArguments.expand(raw, placeholders));
    }

    // 4. Minecraft 启动器标识 (出现在崩溃报告中)
    args.push(`-Dminecraft.launcher.brand=${AppVersion.BRAND}`);
    args.push(`-Dminecraft.launcher.version=${AppVersion.VERSION_NAME}`);

    // 5. 额外 JVM 参数 (用户设置)
    config.extraJVMArgs.forEach(arg => {
      if (arg.trim().length > 0) {
        args.push(arg);
      }
    });

    // 6. 原生库路径
    const nativesDir = `${mcDir}/natives`;
    args.push(`-Djava.library.path=${nativesDir}`);

    // 7. classpath (按版本 libraries 构建)
    args.push('-cp');
    args.push(this.buildClasspath(config, version));

    // 8. 主类
    args.push(this.getMainClass(config, version));

    // 9. 游戏参数
    for (const gameArg of this.buildGameArgs(config, version, instanceDir, placeholders)) {
      args.push(gameArg);
    }

    return args;
  }

  /**
   * 构建启动参数占位符表
   */
  private buildPlaceholders(config: LaunchConfig, version: GameVersion, mcDir: string,
    instanceDir: string): Map<string, string> {
    const map: Map<string, string> = new Map();
    map.set('auth_player_name', config.authUsername);
    map.set('auth_uuid', config.authUUID);
    map.set('auth_access_token', config.authAccessToken);
    map.set('auth_session', `${config.authAccessToken}:${config.authUUID}`);
    map.set('auth_xuid', '');
    map.set('clientid', '');
    map.set('version_name', config.version);
    // game_directory 指向实例目录（整合包隔离：mods / config / saves 在此）
    map.set('game_directory', instanceDir);
    map.set('assets_root', `${mcDir}/assets`);
    map.set('game_assets', `${mcDir}/assets/virtual/legacy`);
    map.set('assets_index_name', version.assetIndex?.id ?? config.version);
    map.set('version_type', version.type ?? 'release');
    map.set('user_type', config.authUserType ?? 'msa');
    map.set('user_properties', '{}');
    map.set('resolution_width', config.windowWidth.toString());
    map.set('resolution_height', config.windowHeight.toString());
    map.set('natives_directory', `${mcDir}/natives`);
    map.set('classpath', this.buildClasspath(config, version));
    map.set('launcher_name', AppVersion.BRAND);
    map.set('launcher_version', AppVersion.VERSION_NAME);
    map.set('library_directory', `${mcDir}/libraries`);
    map.set('authlib_injector_path', '');
    return map;
  }

  /**
   * 构建 classpath
   *
   * 严格按版本 JSON 的 libraries 列表构建 (不再扫描整个 libraries 目录,
   * 否则会混入其它版本的库并导致启动失败)
   */
  private buildClasspath(config: LaunchConfig, version: GameVersion): string {
    const parts: string[] = [];

    // 客户端 JAR (继承型版本指向父版本目录)
    const ownerId = version.clientJarId ?? config.version;
    const versionJar = `${config.gameDir}/versions/${ownerId}/${ownerId}.jar`;
    if (FileUtils.exists(versionJar)) {
      parts.push(versionJar);
    } else {
      // 回退: 版本自身目录
      const fallback = `${config.gameDir}/versions/${config.version}/${config.version}.jar`;
      if (FileUtils.exists(fallback)) {
        parts.push(fallback);
      }
    }

    // 依赖库
    for (const lib of version.libraries ?? []) {
      if (!LibraryRules.isAllowed(lib)) {
        continue;
      }
      const path = this.libraryFilePath(lib, config.gameDir);
      if (path.length > 0 && FileUtils.exists(path)) {
        parts.push(path);
      }
    }

    return parts.join(':');
  }

  /**
   * 计算库文件的绝对路径
   */
  private libraryFilePath(lib: Library, mcDir: string): string {
    const artifact = lib.downloads?.artifact;
    if (artifact && artifact.path.length > 0) {
      return `${mcDir}/libraries/${artifact.path}`;
    }
    // 回退: 由 Maven 坐标推导
    const derived = LibraryRules.libraryPath(lib.name);
    return derived.length > 0 ? `${mcDir}/libraries/${derived}` : '';
  }

  /**
   * 构建游戏参数 (传给 Minecraft 主类)
   *
   * 优先使用版本 JSON 的 arguments.game (含条件对象求值),
   * 老版本 (无 arguments.game) 走手工参数
   */
  private buildGameArgs(config: LaunchConfig, version: GameVersion, instanceDir: string,
    placeholders: Map<string, string>): string[] {
    const args: string[] = [];

    const versionGameArgs = version.arguments?.game ?? [];
    if (versionGameArgs.length > 0) {
      for (const raw of versionGameArgs) {
        args.push(VersionArguments.expand(raw, placeholders));
      }
    } else {
      // 老版本参数格式
      args.push('--username', config.authUsername);
      args.push('--version', config.version);
      args.push('--gameDir', instanceDir);
      // assets 与 libraries 始终共享 gameDir（不随实例隔离）
      args.push('--assetsDir', `${config.gameDir}/assets`);
      args.push('--assetIndex', version.assetIndex?.id ?? config.version);
      args.push('--uuid', config.authUUID);
      args.push('--accessToken', config.authAccessToken);
      args.push('--userType', config.authUserType ?? 'msa');
      args.push('--versionType', version.type ?? 'release');
    }

    // 全屏
    if (config.fullscreen) {
      args.push('--fullscreen');
    } else {
      args.push('--width', config.windowWidth.toString());
      args.push('--height', config.windowHeight.toString());
    }

    // 直连服务器
    if (config.serverAddress) {
      const parts = config.serverAddress.split(':');
      args.push('--server', parts[0]);
      if (parts.length > 1 && parts[1].length > 0) {
        args.push('--port', parts[1]);
      }
    }

    // 演示模式
    if (config.demo) {
      args.push('--demo');
    }

    return args;
  }

  /**
   * 获取主类名
   * 优先用继承链解析出的 mainClass, 其次看是否为加载器版本
   */
  private getMainClass(config: LaunchConfig, version: GameVersion): string {
    if (version.mainClass && version.mainClass.length > 0) {
      return version.mainClass;
    }
    // Forge/Fabric 加载器版本的 mainClass 通常在父版本, 缺失时用通用入口
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
  async launchGame(config: LaunchConfig, version?: GameVersion): Promise<LaunchResult> {
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

      // 解析版本信息（含 inheritsFrom 继承链）
      const resolved = version ?? this.resolveLocalVersion(config.version);
      if (!resolved) {
        return {
          success: false,
          error: `Version ${config.version} not installed. Please download it first.`
        };
      }

      // 验证游戏文件
      const ownerId = resolved.clientJarId ?? config.version;
      const versionJar = `${config.gameDir}/versions/${ownerId}/${ownerId}.jar`;
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

      // 同步上游 FCL 1.3.4.0/1.3.4.1：按游戏版本修补 FML 早期加载屏配置
      // 26.3+ 写入 earlyWindowControl = false（避免 gralloc 争用导致 UI 冻死）
      // 26.3 以下清除残留键（恢复 Forge 模组加载进度动画）
      try {
        // fml.toml 写在实例目录（整合包隔离），版本 JSON 仍从 gameDir 读
        const instanceDir = config.instanceDir ?? config.gameDir;
        const hasFml = FmlConfigPatcher.detectFml(config.gameDir, config.version);
        FmlConfigPatcher.patch(config.gameDir, config.version, hasFml, instanceDir);
      } catch (err) {
        hilog.warn(0x0000, TAG, `fml.toml patch skipped: ${err}`);
      }

      // 构建命令行（native 侧解析 -Xmx / -cp / 主类 / --gameDir）
      const commandArgs = this.buildLaunchCommand(config, resolved);
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
      this.rememberVersion(config.version);

      // ============ NAPI 调用：进程内嵌入 JVM 并运行主类 ============
      // 阻塞语义由 Promise 承载：native 侧在 libuv 工作线程 jvmInit + jvmCallMain，
      // 游戏 main() 返回后 resolve 退出码。此 await 挂起直到游戏退出。
      // 渲染器选择（RendererPage 设置，持久化于 SettingsManager.renderer）激活
      // AMCL GraphicsPlan：mobileglues → GL→GLES 翻译；mobilegl → DirectVulkan（MC 26.3+）
      let renderer: string = 'mobileglues';
      const persisted: string = this.settingsManager.settings.renderer;
      if (persisted.length > 0) {
        renderer = persisted;
      }
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
   * 从本地版本 JSON 解析版本信息 (含 inheritsFrom 继承链)
   * 纯本地读取, 不发起网络请求
   */
  resolveLocalVersion(versionId: string): GameVersion | null {
    const chain: GameVersion[] = [];
    let currentId = versionId;
    const visited: Set<string> = new Set();

    while (currentId.length > 0 && !visited.has(currentId)) {
      visited.add(currentId);
      const jsonPath = `${FileUtils.getVersionsDir()}/${currentId}/${currentId}.json`;
      const raw = FileUtils.readJSON<Record<string, Object>>(jsonPath);
      if (!raw) {
        break;
      }
      const parsed = this.parseLocalVersion(raw, currentId);
      chain.push(parsed);
      currentId = parsed.inheritsFrom ?? '';
    }

    if (chain.length === 0) {
      return null;
    }
    return this.mergeLocalChain(chain, versionId);
  }

  /** 解析本地版本 JSON */
  private parseLocalVersion(raw: Record<string, Object>, fallbackId: string): GameVersion {
    const argsRaw = raw['arguments'] as Object | undefined;
    const parsedArgs = VersionArguments.parse(argsRaw);
    const libraries: Library[] = [];
    const libsRaw = raw['libraries'] as Array<Record<string, Object>> | undefined;
    if (libsRaw) {
      for (const lib of libsRaw) {
        libraries.push({
          name: lib['name'] as string ?? '',
          downloads: lib['downloads'] as LibraryDownloads,
          natives: lib['natives'] as Record<string, string>,
          rules: lib['rules'] as LibraryRule[],
          url: lib['url'] as string
        });
      }
    }
    const idVal = raw['id'] as string;
    const typeVal = raw['type'] as VersionType;
    const inheritsVal = raw['inheritsFrom'] as string;
    const mainClassVal = raw['mainClass'] as string;
    const releaseVal = raw['releaseTime'] as string;
    return {
      id: idVal ?? fallbackId,
      type: typeVal ?? VersionType.RELEASE,
      inheritsFrom: inheritsVal,
      mainClass: mainClassVal ?? '',
      downloads: this.parseLocalDownloads(raw['downloads']),
      arguments: parsedArgs,
      libraries: libraries,
      assetIndex: raw['assetIndex'] as AssetIndex,
      javaVersion: raw['javaVersion'] as JavaVersion,
      releaseTime: releaseVal ?? ''
    };
  }

  /** 解析本地 downloads 段 */
  private parseLocalDownloads(raw: Object | undefined): VersionDownloads | undefined {
    if (!raw) {
      return undefined;
    }
    const obj = raw as Record<string, Object>;
    const result: VersionDownloads = {};
    const clientRaw = obj['client'];
    if (clientRaw) {
      const c = clientRaw as Record<string, Object>;
      result.client = {
        path: c['path'] as string ?? '',
        sha1: c['sha1'] as string ?? '',
        size: c['size'] as number ?? 0,
        url: c['url'] as string ?? ''
      };
    }
    const serverRaw = obj['server'];
    if (serverRaw) {
      const s = serverRaw as Record<string, Object>;
      result.server = {
        path: s['path'] as string ?? '',
        sha1: s['sha1'] as string ?? '',
        size: s['size'] as number ?? 0,
        url: s['url'] as string ?? ''
      };
    }
    return result;
  }

  /** 合并本地继承链 (父 → 子) */
  private mergeLocalChain(chain: GameVersion[], versionId: string): GameVersion {
    const merged: GameVersion = {
      id: chain[0].id,
      type: chain[0].type,
      mainClass: chain[0].mainClass,
      arguments: { game: [], jvm: [] },
      libraries: [],
      assetIndex: undefined,
      javaVersion: undefined,
      releaseTime: chain[0].releaseTime,
      downloads: chain[0].downloads
    };

    for (let i = chain.length - 1; i >= 0; i--) {
      const v = chain[i];
      if (v.mainClass && v.mainClass.length > 0) {
        merged.mainClass = v.mainClass;
      }
      if (v.assetIndex) {
        merged.assetIndex = v.assetIndex;
      }
      if (v.javaVersion) {
        merged.javaVersion = v.javaVersion;
      }
      if (v.downloads && v.downloads.client) {
        merged.downloads = v.downloads;
        merged.clientJarId = v.id;
      }
      for (const lib of v.libraries) {
        const idx = merged.libraries.findIndex(l => l.name === lib.name);
        if (idx >= 0) {
          merged.libraries[idx] = lib;
        } else {
          merged.libraries.push(lib);
        }
      }
      merged.arguments.game = this.mergeArgs(merged.arguments.game, v.arguments?.game ?? []);
      merged.arguments.jvm = this.mergeArgs(merged.arguments.jvm, v.arguments?.jvm ?? []);
    }

    // 依赖库二次去重: 同 groupId:artifactId 保留最高版本
    merged.libraries = LibraryRules.uniqueLibraries(merged.libraries);

    merged.id = versionId;
    return merged;
  }

  /** 合并参数 (同 key 由子覆盖) */
  private mergeArgs(base: string[], override: string[]): string[] {
    const overridden: Set<string> = new Set();
    for (const arg of override) {
      const key = this.argKey(arg);
      if (key.length > 0) {
        overridden.add(key);
      }
    }
    const result: string[] = [];
    for (const arg of base) {
      const key = this.argKey(arg);
      if (key.length === 0 || !overridden.has(key)) {
        result.push(arg);
      }
    }
    for (const arg of override) {
      result.push(arg);
    }
    return result;
  }

  /** 提取参数标识用于覆盖判定 */
  private argKey(arg: string): string {
    if (arg.startsWith('--')) {
      const space = arg.indexOf(' ');
      return space > 0 ? arg.substring(0, space) : arg;
    }
    if (arg.startsWith('-D')) {
      const eq = arg.indexOf('=');
      return eq > 0 ? arg.substring(0, eq) : arg;
    }
    return '';
  }

  /**
   * 记录最近一次启动的版本 (供多人页直连等场景复用)
   */
  private static readonly LAST_VERSION_FILE = 'fcl_last_version.txt';

  private rememberVersion(versionId: string): void {
    try {
      FileUtils.writeText(`${AppContext.filesDir}/${GameLauncherService.LAST_VERSION_FILE}`, versionId);
    } catch (err) {
      hilog.warn(0x0000, TAG, `failed to remember last version: ${err}`);
    }
  }

  /** 获取最近一次启动的版本 (无记录则回落到第一个已安装版本) */
  getLastLaunchedVersion(): string {
    const remembered = FileUtils.readText(
      `${AppContext.filesDir}/${GameLauncherService.LAST_VERSION_FILE}`);
    if (remembered !== null && remembered.trim().length > 0) {
      return remembered.trim();
    }
    const versionsDir = FileUtils.getVersionsDir();
    const dirs = FileUtils.listFiles(versionsDir);
    for (const dir of dirs) {
      if (FileUtils.exists(`${versionsDir}/${dir}/${dir}.json`)) {
        return dir;
      }
    }
    return '';
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
