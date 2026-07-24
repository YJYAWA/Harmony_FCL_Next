/**
 * 游戏库分析器 - 检测模组加载器、分析版本结构
 * 移植自: FCLCore/download/LibraryAnalyzer.java (378行, 核心逻辑)
 *
 * 功能: 从已安装版本中检测 Forge/Fabric/NeoForge/OptiFine/Quilt/LiteLoader
 */
import { GameVersion, Library, ModLoaderType } from './GameTypes';

/** 模组加载器检测结果 */
export interface LoaderDetection {
  type: ModLoaderType;
  version: string;
  libraryId: string;
}

/** 主类常量 */
const VANILLA_MAIN = 'net.minecraft.client.main.Main';
const LAUNCH_WRAPPER_MAIN = 'net.minecraft.launchwrapper.Launch';
const MOD_LAUNCHER_MAIN = 'cpw.mods.modlauncher.Launcher';
const BOOTSTRAP_LAUNCHER_MAIN = 'cpw.mods.bootstraplauncher.BootstrapLauncher';

/** 库类型定义 */
interface LibraryTypeDef {
  modLoader: boolean;
  patchId: string;
  groupPattern: RegExp;
  artifactPattern: RegExp;
  modLoaderType: ModLoaderType | null;
}

/** 已知模组加载器库特征 */
const KNOWN_LIBRARY_TYPES: LibraryTypeDef[] = [
  {
    modLoader: true, patchId: 'forge', modLoaderType: ModLoaderType.FORGE,
    groupPattern: /net\.minecraftforge/, artifactPattern: /(forge|fmlloader)/
  },
  {
    modLoader: true, patchId: 'neoforge', modLoaderType: ModLoaderType.NEOFORGE,
    groupPattern: /net\.neoforged/, artifactPattern: /(core|loader)/
  },
  {
    modLoader: true, patchId: 'fabric', modLoaderType: ModLoaderType.FABRIC,
    groupPattern: /net\.fabricmc/, artifactPattern: /fabric-loader/
  },
  {
    modLoader: true, patchId: 'quilt', modLoaderType: ModLoaderType.QUILT,
    groupPattern: /org\.quiltmc/, artifactPattern: /quilt-loader/
  },
  {
    modLoader: true, patchId: 'liteloader', modLoaderType: ModLoaderType.LITELOADER,
    groupPattern: /com\.mumfrey/, artifactPattern: /liteloader/
  },
  {
    modLoader: false, patchId: 'optifine', modLoaderType: null,
    groupPattern: /(net\.)?optifine/, artifactPattern: /^(?!.*launchwrapper).*$/
  },
  {
    modLoader: true, patchId: 'cleanroom', modLoaderType: ModLoaderType.CLEANROOM,
    groupPattern: /com\.cleanroommc/, artifactPattern: /cleanroom/
  },
  {
    modLoader: false, patchId: 'fabric-api', modLoaderType: null,
    groupPattern: /net\.fabricmc/, artifactPattern: /fabric-api/
  },
  {
    modLoader: false, patchId: 'quilt-api', modLoaderType: null,
    groupPattern: /org\.quiltmc/, artifactPattern: /quilt-api/
  }
];

/** Forge Tweak 类名 (用于 1.5.2 ~ 1.12.2) */
const FORGE_TWEAKERS: string[] = [
  'net.minecraftforge.legacy._1_5_2.LibraryFixerTweaker',
  'cpw.mods.fml.common.launcher.FMLTweaker',
  'net.minecraftforge.fml.common.launcher.FMLTweaker'
];

/** OptiFine Tweak 类名 */
const OPTIFINE_TWEAKERS: string[] = [
  'optifine.OptiFineTweaker',
  'optifine.OptiFineForgeTweaker'
];

const LITELOADER_TWEAKER = 'com.mumfrey.liteloader.launch.LiteLoaderTweaker';

/**
 * 库分析器
 */
export class LibraryAnalyzer {
  /**
   * 从版本中检测已安装的模组加载器
   */
  static detectLoaders(version: GameVersion): LoaderDetection[] {
    const detections: LoaderDetection[] = [];
    const libraries = version.libraries ?? [];

    // 检查每个已知库类型
    for (const typeDef of KNOWN_LIBRARY_TYPES) {
      if (!typeDef.modLoader) {
        continue; // 跳过非模组加载器 (OptiFine, API等)
      }

      for (const lib of libraries) {
        if (LibraryAnalyzer.matchesLibrary(lib, typeDef)) {
          const libVersion = LibraryAnalyzer.extractVersion(lib);
          detections.push({
            type: typeDef.modLoaderType!,
            version: libVersion,
            libraryId: typeDef.patchId
          });
          break; // 每种类型只匹配一次
        }
      }
    }

    // 检查主类以确认
    if (version.mainClass) {
      if (version.mainClass === MOD_LAUNCHER_MAIN ||
        version.mainClass === BOOTSTRAP_LAUNCHER_MAIN) {
        // Forge/NeoForge 已通过库检测到
      }
    }

    // 检查版本 patches
    const patches = (version as Record<string, Object>)['patches'] as
      Array<{ id: string; version: string }> | undefined;
    if (patches) {
      for (const patch of patches) {
        const existing = detections.find(d => d.libraryId === patch.id);
        if (existing && patch.version) {
          existing.version = patch.version;
        }
      }
    }

    return detections;
  }

  /**
   * 检查库是否匹配已知类型
   */
  private static matchesLibrary(lib: Library, typeDef: LibraryTypeDef): boolean {
    const name = lib.name ?? '';
    const parts = name.split(':');

    if (parts.length < 3) {
      return false;
    }

    const groupId = parts[0];
    const artifactId = parts[1];

    return typeDef.groupPattern.test(groupId) &&
      typeDef.artifactPattern.test(artifactId);
  }

  /**
   * 从库名称中提取版本号
   */
  private static extractVersion(lib: Library): string {
    const name = lib.name ?? '';
    const parts = name.split(':');
    if (parts.length >= 3) {
      return parts[2];
    }
    return 'unknown';
  }

  /**
   * 检查版本是否为 Modded (含模组加载器)
   */
  static isModded(version: GameVersion): boolean {
    const mainClass = version.mainClass ?? '';

    // 检查主类
    if (mainClass === LAUNCH_WRAPPER_MAIN ||
      mainClass.startsWith('net.minecraftforge') ||
      mainClass.startsWith('net.neoforged') ||
      mainClass.startsWith('net.fabricmc') ||
      mainClass.startsWith('org.quiltmc') ||
      mainClass.startsWith('cpw.mods') ||
      mainClass.startsWith('top.outlands')) {
      return true;
    }

    // 检查库
    return LibraryAnalyzer.detectLoaders(version).length > 0;
  }

  /**
   * 获取模组加载器类型集合
   */
  static getModLoaders(version: GameVersion): ModLoaderType[] {
    return LibraryAnalyzer.detectLoaders(version)
      .map(d => d.type)
      .filter((v, i, a) => a.indexOf(v) === i);
  }

  /**
   * 根据库特征检测 OptiFine 是否安装
   */
  static hasOptiFine(version: GameVersion): boolean {
    const libraries = version.libraries ?? [];
    const optiFineDef = KNOWN_LIBRARY_TYPES.find(t => t.patchId === 'optifine')!;

    for (const lib of libraries) {
      if (LibraryAnalyzer.matchesLibrary(lib, optiFineDef)) {
        return true;
      }
    }

    // 也可以通过 tweak 类检测
    const args = version.arguments;
    if (args?.game) {
      const gameArgs = args.game.join(' ');
      for (const tweaker of OPTIFINE_TWEAKERS) {
        if (gameArgs.includes(tweaker)) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * 获取 Forge 版本 (从库名称中解析)
   */
  static getForgeVersion(version: GameVersion): string | null {
    const forgeVersionPattern = /^([0-9.]+)-(?<forge>[0-9.]+)(-([0-9.]+))?$/;

    for (const lib of version.libraries ?? []) {
      const name = lib.name ?? '';
      const parts = name.split(':');
      if (parts.length >= 3) {
        const libVersion = parts[2];
        const match = libVersion.match(forgeVersionPattern);
        if (match && match.groups) {
          return match.groups['forge'];
        }
      }
    }
    return null;
  }

  /**
   * 根据需要的最低 Java 版本选择 JDK
   */
  static getRequiredJavaVersion(version: GameVersion): number {
    if (version.javaVersion) {
      return version.javaVersion.majorVersion;
    }

    // 基于版本号推测
    const mcVersion = version.id;
    const numericPart = mcVersion.match(/^(\d+)\.(\d+)/);
    if (numericPart) {
      const major = parseInt(numericPart[1]);
      const minor = parseInt(numericPart[2]);

      if (major > 1 || (major === 1 && minor >= 20)) {
        return 17; // 1.20+ → Java 17
      }
      if (major === 1 && minor >= 18) {
        return 17; // 1.18+ → Java 17
      }
    }

    // 默认 Java 8
    return 8;
  }
}
