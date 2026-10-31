/**
 * 版本启动参数解析器
 * 移植自: FCLCore/download/ 中的 VersionArguments / 官方启动器的 arguments 处理逻辑
 *
 * Mojang 版本 JSON 的 arguments.game / arguments.jvm 有两种元素:
 * 1. 纯字符串: 直接追加
 * 2. 条件对象: { rules: [...], value: string | string[] }
 *    只有当 rules 全部匹配当前平台/特性时, 才会追加 value
 *
 * 常见条件:
 * - { "action": "allow", "os": { "name": "osx" } } → 仅 macOS
 * - { "action": "allow", "features": { "is_demo_user": true } } → 仅演示版
 * - { "action": "allow", "features": { "has_custom_resolution": true } } → 仅自定义分辨率
 */
import { LibraryRule, GameArguments } from './GameTypes';
import { LibraryRules, PlatformSpec, HARMONY_PLATFORM } from './LibraryRules';

/**
 * 版本参数解析工具
 */
export class VersionArguments {
  /**
   * 解析 arguments 段
   * @param raw 版本 JSON 中的 arguments 对象
   * @param platform 平台规格
   * @param features 特性开关 (is_demo_user / has_custom_resolution)
   */
  static parse(raw: Object | undefined, platform: PlatformSpec = HARMONY_PLATFORM,
    features?: Map<string, boolean>): GameArguments {
    const result: GameArguments = { game: [], jvm: [] };
    if (!raw) {
      return result;
    }
    const obj = raw as Record<string, Object>;
    result.game = VersionArguments.parseList(obj['game'], platform, features);
    result.jvm = VersionArguments.parseList(obj['jvm'], platform, features);
    return result;
  }

  /** 解析参数数组 (元素可为字符串或条件对象) */
  private static parseList(raw: Object | undefined, platform: PlatformSpec,
    features?: Map<string, boolean>): string[] {
    const result: string[] = [];
    if (!raw || !Array.isArray(raw)) {
      return result;
    }
    const arr = raw as Array<Object>;
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i];
      if (typeof item === 'string') {
        result.push(item);
        continue;
      }
      if (typeof item !== 'object' || item === null) {
        continue;
      }
      const entry = item as Record<string, Object>;

      // 条件对象: rules + value
      const rulesRaw = entry['rules'];
      if (rulesRaw && Array.isArray(rulesRaw)) {
        const rules = rulesRaw as LibraryRule[];
        if (!VersionArguments.rulesMatch(rules, platform, features)) {
          continue;
        }
        VersionArguments.appendValue(result, entry['value']);
        continue;
      }

      // 无 rules 但有 value: 直接追加
      if (entry['value'] !== undefined) {
        VersionArguments.appendValue(result, entry['value']);
      }
    }
    return result;
  }

  /** 追加 value (string 或 string[]) */
  private static appendValue(target: string[], value: Object | undefined): void {
    if (value === undefined) {
      return;
    }
    if (typeof value === 'string') {
      target.push(value);
      return;
    }
    if (Array.isArray(value)) {
      const items = value as Array<Object>;
      for (let i = 0; i < items.length; i++) {
        if (typeof items[i] === 'string') {
          target.push(items[i] as string);
        }
      }
    }
  }

  /**
   * 判断条件规则组是否匹配
   * rules 数组内多条规则为 "与" 关系 (全部匹配才成立)
   */
  private static rulesMatch(rules: LibraryRule[], platform: PlatformSpec,
    features?: Map<string, boolean>): boolean {
    if (rules.length === 0) {
      return true;
    }
    for (const rule of rules) {
      const effective: PlatformSpec = {
        osName: platform.osName,
        osArch: platform.osArch,
        features: features ?? platform.features
      };
      if (!LibraryRules.matches(rule, effective)) {
        return false;
      }
    }
    return true;
  }

  /**
   * 过滤掉启动器需要自己生成的 JVM 参数
   *
   * 官方 JSON 的 arguments.jvm 含:
   * - "-cp" + "${classpath}"   → classpath 由启动器按版本 libraries 自行构建
   * - "-Djava.library.path=${natives_directory}" → 原生库目录由启动器管理
   * - "-Djava.library.path=" 等重复项
   * - "-XstartOnFirstThread"   → 仅 macOS
   */
  static filterJvmArgs(args: string[]): string[] {
    const result: string[] = [];
    let skipNext = false;
    for (const arg of args) {
      if (skipNext) {
        skipNext = false;
        continue;
      }
      if (arg === '-cp' || arg === '-classpath') {
        skipNext = true;
        continue;
      }
      if (arg.startsWith('-Djava.library.path=')) {
        continue;
      }
      if (arg === '-XstartOnFirstThread') {
        continue;
      }
      result.push(arg);
    }
    return result;
  }

  /**
   * 展开启动参数中的占位符
   * 官方占位符: ${auth_player_name} ${auth_uuid} ${auth_access_token} ${version_name}
   * ${game_directory} ${assets_root} ${assets_index_name} ${version_type}
   * ${user_type} ${user_properties} ${resolution_width} ${resolution_height}
   * ${natives_directory} ${classpath} ${launcher_name} ${launcher_version}
   */
  static expand(arg: string, values: Map<string, string>): string {
    let result = arg;
    values.forEach((value: string, key: string) => {
      result = result.replace(`\${${key}}`, value);
    });
    return result;
  }
}
