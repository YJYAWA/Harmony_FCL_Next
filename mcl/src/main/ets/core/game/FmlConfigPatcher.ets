/**
 * FML 早期加载屏配置修补
 *
 * 同步上游 FCL 1.3.4.0 / 1.3.4.1 的修复：
 * - 1.3.4.0：NeoForge 12 起移除了 -Dfml.earlyprogresswindow 属性通道，
 *   FML 只读 config/fml.toml；26.3+ 上 FML 早期加载屏的 ANGLE/Vulkan 渲染线程
 *   在启动扫描期间持续分配 gralloc 缓冲，与启动器 UI 的 present 争用
 *   vendor gralloc 共享锁，导致 RenderThread 无法出帧、界面冻结并触发 ANR。
 *   修复方式是在 fml.toml 中写入 earlyWindowControl = false。
 * - 1.3.4.1：1.3.4.0 的无条件写入会让 26.3 以下版本的 Forge 模组加载
 *   进度动画被误关，因此改为按游戏版本分流：
 *   26.3+ 写入 earlyWindowControl = false；26.3 以下不创建该配置，
 *   并清除旧文件中的残留关闭键，恢复 FML 早期加载屏。
 */
import { FileUtils } from '../util/FileUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-FmlConfig';

export class FmlConfigPatcher {
  private static readonly EARLY_WINDOW_KEY: string = 'earlyWindowControl';

  /**
   * 比较 Minecraft 版本号与阈值 26.3
   * @param versionId 版本 ID（如 "1.21.4"、"26.3"、"26.4-snapshot-1"）
   * @returns >= 26.3 返回 true
   */
  static isAtLeast263(versionId: string): boolean {
    const match = versionId.match(/^(\d+)(?:\.(\d+))?/);
    if (!match) {
      return false;
    }
    const major = parseInt(match[1]);
    const minor = match[2] !== undefined ? parseInt(match[2]) : 0;
    if (major > 26) {
      return true;
    }
    if (major < 26) {
      return false;
    }
    return minor >= 3;
  }

  /**
   * 按游戏版本修补 fml.toml
   * @param gameDir 游戏目录（fml.toml 位于 <gameDir>/config/fml.toml）
   * @param versionId 游戏版本 ID
   * @param hasFml 是否为 FML 系（Forge / NeoForge）版本
   * @returns 是否发生了实际改动
   */
  static patch(gameDir: string, versionId: string, hasFml: boolean): boolean {
    if (!hasFml) {
      return false;
    }

    const configPath = `${gameDir}/config/fml.toml`;
    const shouldDisable = FmlConfigPatcher.isAtLeast263(versionId);

    if (!shouldDisable) {
      // 26.3 以下：清除历史残留的 earlyWindowControl = false，恢复早期加载屏
      if (!FileUtils.exists(configPath)) {
        return false;
      }
      const content = FileUtils.readText(configPath);
      if (!content) {
        return false;
      }
      const cleaned = FmlConfigPatcher.removeEarlyWindowControl(content);
      if (cleaned === content) {
        return false;
      }
      const ok = FileUtils.writeText(configPath, cleaned);
      hilog.info(0x0000, TAG, `fml.toml earlyWindowControl cleared for ${versionId}: ${ok}`);
      return ok;
    }

    // 26.3+：写入 earlyWindowControl = false
    let content = FileUtils.exists(configPath) ? FileUtils.readText(configPath) ?? '' : '';
    if (FmlConfigPatcher.hasEarlyWindowDisabled(content)) {
      return false;
    }
    const updated = FmlConfigPatcher.setEarlyWindowControl(content);
    const ok = FileUtils.writeText(configPath, updated);
    hilog.info(0x0000, TAG, `fml.toml earlyWindowControl=false for ${versionId}: ${ok}`);
    return ok;
  }

  /**
   * 检测指定版本是否为 FML 系（Forge / NeoForge）
   * @param gameDir 游戏目录
   * @param versionId 版本 ID
   */
  static detectFml(gameDir: string, versionId: string): boolean {
    const versionPath = `${gameDir}/versions/${versionId}/${versionId}.json`;
    const raw = FileUtils.readText(versionPath);
    if (!raw) {
      return false;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const mainClass = parsed['mainClass'];
      if (typeof mainClass === 'string' &&
        (mainClass.indexOf('BootstrapLauncher') >= 0 || mainClass.indexOf('bootstraplauncher') >= 0)) {
        return true;
      }
      const libraries = parsed['libraries'];
      if (Array.isArray(libraries)) {
        const libList = libraries as Object[];
        for (const lib of libList) {
          const entry = lib as Record<string, Object>;
          const name = entry['name'];
          if (typeof name === 'string' &&
            (name.indexOf('net.minecraftforge') === 0 || name.indexOf('net.neoforged') === 0)) {
            return true;
          }
        }
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, `Failed to inspect version ${versionId}: ${err}`);
    }
    return false;
  }

  /** 内容中是否已存在 earlyWindowControl = false */
  private static hasEarlyWindowDisabled(content: string): boolean {
    const pattern = /^\s*earlyWindowControl\s*=\s*false\s*$/m;
    return pattern.test(content);
  }

  /** 设置 earlyWindowControl = false（保留其余内容与注释） */
  private static setEarlyWindowControl(content: string): string {
    const cleaned = FmlConfigPatcher.removeEarlyWindowControl(content);
    const base = cleaned.length > 0 && !cleaned.endsWith('\n') ? `${cleaned}\n` : cleaned;
    return `${base}${FmlConfigPatcher.EARLY_WINDOW_KEY} = false\n`;
  }

  /** 移除 earlyWindowControl 键（连同其所在行） */
  private static removeEarlyWindowControl(content: string): string {
    const lines = content.split('\n');
    const kept: string[] = [];
    for (const line of lines) {
      if (/^\s*earlyWindowControl\s*=/.test(line)) {
        continue;
      }
      kept.push(line);
    }
    return kept.join('\n');
  }
}
