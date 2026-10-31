/**
 * 游戏启动构建器
 * 移植自: FCLCore/download/DefaultGameBuilder + GameBuilder
 *
 * 功能: 构建完整的 Minecraft 启动命令行和 JVM 参数
 */
import { GameVersion, LaunchConfig, Library, ModLoaderType } from './GameTypes';
import { Constants } from '../util/Constants';
import { AppVersion } from '../util/AppVersion';
import { FileUtils } from '../util/FileUtils';
import { LibraryAnalyzer } from './LibraryAnalyzer';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-GameBuilder';

/** 启动参数构建结果 */
export interface LaunchCommand {
  /** JVM 可执行文件 */
  javaExecutable: string;
  /** JVM 参数 */
  jvmArgs: string[];
  /** Minecraft 主类 */
  mainClass: string;
  /** 程序参数 */
  gameArgs: string[];
  /** classpath */
  classpath: string[];
  /** 环境变量 */
  envVars: Record<string, string>;
  /** 工作目录 */
  workingDir: string;
}

/**
 * 游戏构建器
 */
export class GameBuilder {
  /**
   * 构建完整启动命令
   */
  static build(config: LaunchConfig, version: GameVersion): LaunchCommand {
    const mcDir = config.gameDir;

    // 1. 选择 Java
    const javaVersion = LibraryAnalyzer.getRequiredJavaVersion(version);
    const javaPath = config.javaPath || 'java';

    // 2. 构建 JVM 参数
    const jvmArgs = GameBuilder.buildJVMArgs(config, version, javaVersion, mcDir);

    // 3. 构建 classpath
    const classpath = GameBuilder.buildClasspath(version, mcDir);

    // 4. 构建游戏参数
    const gameArgs = GameBuilder.buildGameArgs(config, version, mcDir);

    // 5. 确定主类
    const mainClass = GameBuilder.determineMainClass(version);

    // 6. 原生库路径
    const nativesDir = `${mcDir}/natives`;

    return {
      javaExecutable: javaPath,
      jvmArgs: [
        ...jvmArgs,
        `-Djava.library.path=${nativesDir}`
      ],
      mainClass,
      gameArgs,
      classpath,
      envVars: {},
      workingDir: mcDir
    };
  }

  /** 构建 JVM 参数 */
  private static buildJVMArgs(config: LaunchConfig, version: GameVersion,
    javaVersion: number, mcDir: string): string[] {
    const args: string[] = [];

    // 内存
    args.push(`-Xms${config.minMemory}M`);
    args.push(`-Xmx${config.maxMemory}M`);

    // HarmonyOS JIT 必需
    args.push('-XX:+AllowWritableCodeMemory');

    // GC 参数
    if (javaVersion >= 17) {
      args.push('-XX:+UseG1GC');
      args.push('-XX:+ParallelRefProcEnabled');
      args.push('-XX:MaxGCPauseMillis=200');
    }

    // Minecraft 属性
    args.push(`-Dminecraft.client.jar=${mcDir}/versions/${config.version}/${config.version}.jar`);
    args.push(`-Dminecraft.launcher.brand=${AppVersion.BRAND}`);
    args.push(`-Dminecraft.launcher.version=${AppVersion.VERSION_NAME}`);

    // 日志
    args.push('-Dlog4j2.formatMsgNoLookups=true');

    // 额外 JVM 参数
    for (const arg of config.extraJVMArgs) {
      if (arg.trim().length > 0) {
        args.push(arg);
      }
    }

    return args;
  }

  /** 构建 classpath */
  static buildClasspath(version: GameVersion, mcDir: string): string[] {
    const classpath: string[] = [];

    // 版本 JAR
    classpath.push(`${mcDir}/versions/${version.id}/${version.id}.jar`);

    // 依赖库
    for (const lib of version.libraries ?? []) {
      if (!GameBuilder.shouldIncludeLibrary(lib)) {
        continue;
      }

      const artifact = lib.downloads?.artifact;
      if (artifact?.path) {
        classpath.push(`${mcDir}/libraries/${artifact.path}`);
      } else {
        // 从 Maven 坐标构建路径
        const name = lib.name ?? '';
        const parts = name.split(':');
        if (parts.length >= 3) {
          const group = parts[0].replace(/\./g, '/');
          const artifact = parts[1];
          const version = parts[2];
          const path = `${group}/${artifact}/${version}/${artifact}-${version}.jar`;
          classpath.push(`${mcDir}/libraries/${path}`);
        }
      }
    }

    return classpath;
  }

  /** 构建游戏参数 */
  private static buildGameArgs(config: LaunchConfig, version: GameVersion, mcDir: string): string[] {
    const args: string[] = [];

    // 版本指定的游戏参数
    if (version.arguments?.game) {
      for (const arg of version.arguments.game) {
        // 替换占位符
        let resolved = arg
          .replace('${auth_player_name}', config.authUsername)
          .replace('${auth_uuid}', config.authUUID)
          .replace('${auth_access_token}', config.authAccessToken)
          .replace('${version_name}', config.version)
          .replace('${game_directory}', mcDir)
          .replace('${assets_root}', `${mcDir}/assets`)
          .replace('${game_assets}', `${mcDir}/assets`)
          .replace('${assets_index_name}',
            version.assetIndex?.id ?? config.version)
          .replace('${version_type}', 'release')
          .replace('${user_type}', 'mojang')
          .replace('${user_properties}', '{}')
          .replace('${resolution_width}', config.windowWidth.toString())
          .replace('${resolution_height}', config.windowHeight.toString());

        args.push(resolved);
      }
    } else {
      // 旧版参数格式
      args.push('--username', config.authUsername);
      args.push('--version', config.version);
      args.push('--gameDir', mcDir);
      args.push('--assetsDir', `${mcDir}/assets`);
      args.push('--assetIndex', version.assetIndex?.id ?? config.version);
      args.push('--uuid', config.authUUID);
      args.push('--accessToken', config.authAccessToken);
      args.push('--userType', 'mojang');
      args.push('--versionType', 'release');
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
      args.push('--server', config.serverAddress.split(':')[0]);
      const port = config.serverAddress.split(':')[1];
      if (port) {
        args.push('--port', port);
      }
    }

    // 演示模式
    if (config.demo) {
      args.push('--demo');
    }

    return args;
  }

  /** 确定主类 */
  static determineMainClass(version: GameVersion): string {
    // 已安装版本: 使用版本 JSON 中的 mainClass
    if (version.mainClass) {
      return version.mainClass;
    }

    // 检查模组加载器
    const loaders = LibraryAnalyzer.detectLoaders(version);

    if (loaders.some(l => l.type === ModLoaderType.FABRIC)) {
      return 'net.fabricmc.loader.impl.launch.knot.KnotClient';
    }

    if (loaders.some(l => l.type === ModLoaderType.FORGE)) {
      return 'cpw.mods.bootstraplauncher.BootstrapLauncher';
    }

    // 默认
    return 'net.minecraft.client.main.Main';
  }

  /** 判断库是否应包含在 classpath 中 */
  static shouldIncludeLibrary(lib: Library): boolean {
    if (!lib.rules || lib.rules.length === 0) {
      return true;
    }

    let allowed = false;
    for (const rule of lib.rules) {
      if (rule.os) {
        // HarmonyOS NEXT: 不是 Windows/Mac/Linux, 需要特殊处理
        // 暂时允许所有
        allowed = rule.action === 'allow';
      } else if (rule.features) {
        allowed = rule.action === 'allow';
      }
    }

    return allowed;
  }

  /** 获取合并后的命令行字符串 (用于显示) */
  static toCommandLine(command: LaunchCommand): string {
    const parts: string[] = [
      command.javaExecutable,
      ...command.jvmArgs,
      '-cp',
      command.classpath.join(':'),
      command.mainClass,
      ...command.gameArgs
    ];
    return parts.join(' ');
  }

  /** 获取 classpath 字符串 */
  static toClasspathString(command: LaunchCommand): string {
    return command.classpath.join(':');
  }
}
