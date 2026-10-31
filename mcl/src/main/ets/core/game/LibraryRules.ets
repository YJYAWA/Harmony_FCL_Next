/**
 * 依赖库规则判定器
 * 移植自: FCLCore/download/ 中的 LibraryRule 判定逻辑 (Mojang 官方 rules 语义)
 *
 * 语义 (与 Mojang 启动器一致):
 * 1. 库没有 rules → 一律允许
 * 2. 有 rules → 按顺序求值, 最后一条"匹配"的规则决定结果
 * 3. 规则匹配条件:
 *    - os.name / os.arch / os.version 三者都匹配 (未声明的字段视为匹配)
 *    - features: 声明的 feature 必须为 true 才算匹配
 *
 * HarmonyOS NEXT 平台判定:
 * - os.name  : 视为 'linux'   (OHOS 内核与 Linux 兼容, LWJGL/Mesa 走 Linux 分支)
 * - os.arch  : 视为 'arm64'   (等价 aarch64)
 * - os.version: 不做版本匹配 (OHOS 与 Linux 内核版本号不可比)
 */
import { Library, LibraryRule } from './GameTypes';
import { parseMavenName, compareMavenVersions } from './MavenCoords';

/** 当前运行平台的能力描述 */
export interface PlatformSpec {
  /** 操作系统名 (Mojang 约定值) */
  osName: string;
  /** CPU 架构 (Mojang 约定值) */
  osArch: string;
  /** 启用的游戏特性 (features) */
  features: Map<string, boolean>;
}

/** HarmonyOS NEXT 平台规格 */
export const HARMONY_PLATFORM: PlatformSpec = {
  osName: 'linux',
  osArch: 'arm64',
  features: new Map<string, boolean>()
};

/**
 * 库规则判定工具
 */
export class LibraryRules {
  /**
   * 判断库在当前平台是否应被包含
   */
  static isAllowed(lib: Library, platform: PlatformSpec = HARMONY_PLATFORM): boolean {
    const rules = lib.rules;
    if (!rules || rules.length === 0) {
      return true;
    }

    let allowed = true;
    for (const rule of rules) {
      if (LibraryRules.matches(rule, platform)) {
        allowed = rule.action === 'allow';
      }
    }
    return allowed;
  }

  /** 判断单条规则是否在当前平台匹配 */
  static matches(rule: LibraryRule, platform: PlatformSpec): boolean {
    if (rule.os) {
      const name = rule.os.name;
      if (name !== undefined && name.length > 0 && name !== platform.osName) {
        return false;
      }
      const arch = rule.os.arch;
      if (arch !== undefined && arch.length > 0 && arch !== platform.osArch) {
        return false;
      }
      // os.version 为正则表达式 (如 "^10\\."), HarmonyOS 平台不参与匹配
      const version = rule.os.version;
      if (version !== undefined && version.length > 0) {
        const osVersion = LibraryRules.currentOsVersion();
        if (osVersion.length === 0) {
          return false;
        }
        try {
          const re = new RegExp(version);
          if (!re.test(osVersion)) {
            return false;
          }
        } catch {
          return false;
        }
      }
    }

    if (rule.features) {
      const features = rule.features as Record<string, boolean>;
      for (const key of Object.keys(features)) {
        const expected = features[key];
        const actual = platform.features.get(key) ?? false;
        if (expected !== actual) {
          return false;
        }
      }
    }

    return true;
  }

  /**
   * 获取当前系统版本字符串 (用于 os.version 正则匹配)
   * HarmonyOS NEXT 无可比对的 Linux 内核版本, 返回空串表示不匹配
   */
  private static currentOsVersion(): string {
    return '';
  }

  /**
   * 选择该库在当前平台对应的 native classifier
   * 优先 linux-arm64 → linux → 无
   */
  static nativeClassifier(lib: Library, platform: PlatformSpec = HARMONY_PLATFORM): string {
    const natives = lib.natives;
    if (!natives) {
      return '';
    }
    const keys = Object.keys(natives);
    if (keys.length === 0) {
      return '';
    }
    // 精确匹配: linux-arm64 / linux-aarch64
    for (const key of keys) {
      if (key === `${platform.osName}-${platform.osArch}` || key === `${platform.osName}-aarch64`) {
        return key;
      }
    }
    // 退到通用 linux
    for (const key of keys) {
      if (key === platform.osName) {
        return key;
      }
    }
    return '';
  }

  /**
   * 依赖库去重 (移植 AMCL VersionJsonMerger.uniqueLibraries)
   *
   * 按 groupId:artifactId(:classifier) 分组, 同组保留**最高版本**。
   * 这是必要的: Fabric 与原版同时声明 org.ow2.asm:asm 时,
   * 若两份都进 classpath 会触发 IllegalStateException。
   * 无法解析坐标的库原样保留 (不冒险去重)。
   */
  static uniqueLibraries(libs: Library[]): Library[] {
    const out: Library[] = [];
    const keyToIndex: Map<string, number> = new Map();

    for (const lib of libs) {
      const coord = parseMavenName(lib.name);
      if (!coord) {
        out.push(lib);
        continue;
      }
      const key = `${coord.groupId}:${coord.artifactId}` +
        (coord.classifier ? `:${coord.classifier}` : '');
      const existingIdx = keyToIndex.get(key);
      if (existingIdx === undefined) {
        keyToIndex.set(key, out.length);
        out.push(lib);
        continue;
      }
      const existing = out[existingIdx];
      const existingCoord = parseMavenName(existing.name);
      const existingVer = existingCoord ? existingCoord.version : '0';
      if (compareMavenVersions(coord.version, existingVer) > 0) {
        out[existingIdx] = lib;
      }
    }
    return out;
  }

  /**
   * 由 Maven 坐标推导库文件相对路径
   * 例: "org.lwjgl:lwjgl:3.3.1" → "org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1.jar"
   */
  static libraryPath(name: string): string {
    const parts = name.split(':');
    if (parts.length < 3) {
      return '';
    }
    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const classifier = parts.length >= 4 ? `-${parts[3]}` : '';
    return `${group}/${artifact}/${version}/${artifact}-${version}${classifier}.jar`;
  }
}
