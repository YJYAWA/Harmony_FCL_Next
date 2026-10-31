/**
 * 游戏数据存储位置解析器
 *
 * 移植自 AMCL: feature_system/src/main/ets/GameStorage.ets
 *
 * 为什么必须有这个：HarmonyOS NEXT 的沙箱 filesDir 在应用卸载时被一并删除，
 * 游戏版本 / 存档 / 模组全部丢失。AMCL 的做法是提供「沙箱内 / 沙箱外」双位置：
 *
 *   - SANDBOX  : filesDir + '/.minecraft'（默认，卸载即删）
 *   - EXTERNAL : <Download>/com.harmony.fcl/.minecraft（卸载不丢）
 *
 * 设备能力分叉（对齐 AMCL 的 canIUse FolderObtain 分支）：
 *   - 平板/2in1：Environment.getUserDownloadDir() 实时取 Download 根，需 READ_WRITE_DOWNLOAD_DIRECTORY；
 *   - 手机    ：getUserDownloadDir 报 801 → 改用 DocumentViewPicker DOWNLOAD 模式「学」一次
 *               公共应用目录路径，落盘 Preferences 后按原始路径使用（所有权式访问，跨重启有效，
 *               无需 persist/activate）。
 *
 * 运行时产物（JDK / cacert / 日志 / 安装器沙箱）始终留在沙箱 —— 它们随安装重建，
 * 且 JDK 的 .so 必须由 ELF loader 从沙箱加载，不能挪到公共目录。
 */
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { Environment, fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppContext } from '../../common/AppContext';

const TAG = 'FCL-GameStorage';

const DOWNLOAD_PERM: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';

/** 平板静默路线能力 */
const SYSCAP_TABLET_SILENT = 'SystemCapability.FileManagement.File.Environment.FolderObtain';

/** 外部公共目录里的应用文件夹名 = 包名，文件管理器会识别为已安装应用并进「来源」侧栏 */
const EXTERNAL_FOLDER = 'com.harmony.fcl';

/** 存储位置 */
export enum StorageLocation {
  SANDBOX = 'sandbox',
  EXTERNAL = 'external'
}

/** 把持久化的字符串还原成枚举（未知值 → 沙箱） */
export function parseStorageLocation(s: string): StorageLocation {
  return s === StorageLocation.EXTERNAL ? StorageLocation.EXTERNAL : StorageLocation.SANDBOX;
}

/**
 * 系统能力检测
 *
 * AMCL 用 ArkTS 全局 canIUse（@internal/full/global.d.ts）。本项目当前 SDK 暴露
 * 了同名全局函数，但为兼容不同 SDK 版本，这里做两段式判断：
 *   1. 尝试调用全局 canIUse；
 *   2. 不可用时按 deviceInfo.deviceType 推断（tablet / 2in1 视为具备平板静默路线）。
 */
function hasSyscap(syscap: string): boolean {
  try {
    if (typeof canIUse === 'function') {
      return canIUse(syscap);
    }
  } catch {
    // 落到设备类型推断
  }
  try {
    const deviceType = deviceInfo.deviceType;
    return deviceType === 'tablet' || deviceType === '2in1';
  } catch {
    return false;
  }
}

export class GameStorage {
  private static cachedDownloadDir: string = '';
  private static downloadDirTried: boolean = false;

  /** 手机端「学」到的外部应用目录（…/Download/com.harmony.fcl）。'' = 尚未学过 */
  private static phoneExternalDir: string = '';

  /** 注入手机端缓存的外部应用目录（启动期由 EntryAbility 调用） */
  static setPhoneExternalDir(dir: string): void {
    GameStorage.phoneExternalDir = (dir && dir.length > 0) ? dir : '';
  }

  /** 平板静默路线是否可用（决定 externalAppDir 走 Environment 还是手机缓存路径） */
  static isTabletSilent(): boolean {
    return hasSyscap(SYSCAP_TABLET_SILENT);
  }

  /**
   * Download 根路径（平板路线）。取不到返回 ''。结果缓存。
   */
  static downloadDir(): string {
    if (!GameStorage.downloadDirTried) {
      GameStorage.downloadDirTried = true;
      try {
        const d = Environment.getUserDownloadDir();
        GameStorage.cachedDownloadDir = (d && d.length > 0) ? d : '';
      } catch (err) {
        hilog.warn(0x0000, TAG, `getUserDownloadDir failed: ${err}`);
        GameStorage.cachedDownloadDir = '';
      }
    }
    return GameStorage.cachedDownloadDir;
  }

  /** 沙箱内 .minecraft 根 */
  static sandboxMcDir(): string {
    return `${AppContext.filesDir}/.minecraft`;
  }

  /** 外部应用目录（…/Download/com.harmony.fcl）；不可用返回 '' */
  static externalAppDir(): string {
    if (GameStorage.isTabletSilent()) {
      const d = GameStorage.downloadDir();
      return d.length > 0 ? `${d}/${EXTERNAL_FOLDER}` : '';
    }
    return GameStorage.phoneExternalDir;
  }

  /** 外部游戏数据根（…/com.harmony.fcl/.minecraft）；不可用返回 '' */
  static externalMcDir(): string {
    const app = GameStorage.externalAppDir();
    return app.length > 0 ? `${app}/.minecraft` : '';
  }

  /**
   * 解析当前激活的 .minecraft 根（同步，可在热路径调用）
   * EXTERNAL 但外部不可用 → 回落沙箱，保证永远返回可用路径
   */
  static resolveMcDir(location: StorageLocation): string {
    if (location === StorageLocation.EXTERNAL) {
      const ext = GameStorage.externalMcDir();
      if (ext.length > 0) {
        return ext;
      }
      hilog.warn(0x0000, TAG, 'EXTERNAL selected but unavailable; fallback to sandbox');
    }
    return GameStorage.sandboxMcDir();
  }

  /** 外部存储是否「已就绪能直接用」 */
  static isExternalAvailable(): boolean {
    return GameStorage.externalAppDir().length > 0;
  }

  /** 外部存储是否「可启用」（UI 是否允许点「外部」） */
  static isExternalSupported(): boolean {
    return GameStorage.isTabletSilent() ? (GameStorage.downloadDir().length > 0) : true;
  }

  /** 手机端是否还需先跑 picker 学路径 */
  static needsPhoneLearn(): boolean {
    return !GameStorage.isTabletSilent() && GameStorage.phoneExternalDir.length === 0;
  }

  /**
   * 手机：用 DocumentViewPicker DOWNLOAD 模式「学」一次公共应用目录原始路径。
   * 返回 …/Download/com.harmony.fcl；取消/失败返回 ''。
   */
  private static async learnPhoneExternalDir(): Promise<string> {
    try {
      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const vp = new picker.DocumentViewPicker(AppContext.context as common.UIAbilityContext);
      const uris: string[] = await vp.save(opts);
      if (!uris || uris.length === 0) {
        return '';
      }
      return new fileUri.FileUri(uris[0]).path;
    } catch (err) {
      hilog.warn(0x0000, TAG, `learnPhoneExternalDir failed: ${err}`);
      return '';
    }
  }

  /**
   * 确保已学到外部应用目录。已学过直接返回，否则 picker 学一次并落盘 + 注入。
   * 返回 appDir 或 ''（取消/失败）。
   */
  static async ensurePhoneExternalDir(): Promise<string> {
    if (GameStorage.phoneExternalDir.length > 0) {
      return GameStorage.phoneExternalDir;
    }
    const dir = await GameStorage.learnPhoneExternalDir();
    if (dir.length === 0) {
      return '';
    }
    // 校验：其下能有 .minecraft 目录才算真就绪
    // 注意：HarmonyOS fs.mkdirSync(path, true) 在目录已存在时仍会抛 EEXIST，
    // 故 mkdir 仅 best-effort，真正以 statSync 确认目录存在为准。
    try {
      fs.mkdirSync(`${dir}/.minecraft`, true);
    } catch (err) {
      hilog.debug(0x0000, TAG, `mkdir .minecraft (may exist): ${err}`);
    }
    try {
      const st = fs.statSync(`${dir}/.minecraft`);
      if (!st.isDirectory()) {
        hilog.warn(0x0000, TAG, 'ensurePhoneExternalDir: .minecraft exists but not a directory');
        return '';
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, `ensurePhoneExternalDir verify failed: ${err}`);
      return '';
    }
    GameStorage.setPhoneExternalDir(dir);
    hilog.info(0x0000, TAG, `learned phone external dir: ${dir}`);
    return dir;
  }

  /** 同步查询 READ_WRITE_DOWNLOAD_DIRECTORY 是否已授权（仅平板路线需要） */
  static isDownloadPermissionGranted(): boolean {
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const tokenId = AppContext.context.applicationInfo.accessTokenId;
      const status = atm.checkAccessTokenSync(tokenId, DOWNLOAD_PERM);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      hilog.warn(0x0000, TAG, `checkAccessTokenSync failed: ${err}`);
      return false;
    }
  }

  /** 运行时申请 READ_WRITE_DOWNLOAD_DIRECTORY；返回是否已授权 */
  static async requestDownloadPermission(): Promise<boolean> {
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = [DOWNLOAD_PERM];
      const res = await atm.requestPermissionsFromUser(
        AppContext.context as common.UIAbilityContext, perms);
      const code: number = (res.authResults && res.authResults.length > 0) ? res.authResults[0] : -1;
      return code === 0;
    } catch (err) {
      hilog.warn(0x0000, TAG, `requestPermissionsFromUser failed: ${err}`);
      return false;
    }
  }

  /** 是否存在已安装版本（versions 目录非空）。用于切换位置时判断要不要问迁移 */
  static hasVersions(mcDir: string): boolean {
    try {
      const entries = fs.listFileSync(`${mcDir}/versions`);
      return entries.length > 0;
    } catch (err) {
      return false;
    }
  }

  /**
   * 把整个游戏数据从 fromMcDir 复制迁移到 toMcDir（源数据保留不删，更安全）。
   */
  static async migrate(fromMcDir: string, toMcDir: string): Promise<void> {
    try {
      fs.mkdirSync(toMcDir, true);
    } catch (err) {
      hilog.debug(0x0000, TAG, `mkdir target (may exist): ${err}`);
    }
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(fromMcDir);
    } catch (err) {
      hilog.warn(0x0000, TAG, `migrate list source failed: ${err}`);
      return;
    }
    for (const name of entries) {
      const src = `${fromMcDir}/${name}`;
      try {
        const st = fs.statSync(src);
        if (st.isDirectory()) {
          await fs.copyDir(src, toMcDir, 1);
        } else {
          fs.copyFileSync(src, `${toMcDir}/${name}`);
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, `migrate skip ${name}: ${err}`);
      }
    }
    hilog.info(0x0000, TAG, `migrated game data: ${fromMcDir} -> ${toMcDir}`);
  }

  /**
   * 在外部 / 沙箱目录下写一份说明 txt，引导用户开启「显示隐藏文件」。
   * 写-if-absent：已存在则不覆盖。
   */
  static writeHints(): void {
    GameStorage.writeHint(AppContext.filesDir, '应用内（沙箱）',
      '沙箱目录会随应用卸载一并删除（不保留）。');
    const appDir = GameStorage.externalAppDir();
    if (appDir.length > 0) {
      GameStorage.writeHint(appDir, '公共下载目录',
        '本文件夹在公共下载目录里，卸载应用也不会被删除。');
    }
  }

  private static writeHint(dir: string, title: string, note: string): void {
    const hintPath = `${dir}/请开启“显示隐藏文件”查看游戏数据.txt`;
    try {
      fs.statSync(hintPath);
      return;
    } catch (err) {
      // 不存在，继续写
    }
    const content = `FCL 游戏数据说明（${title}）\n` +
      '========================\n\n' +
      '你的 Minecraft 游戏数据（版本 versions / 存档 saves / 模组 mods / 资源 assets 等）\n' +
      '都保存在本文件夹下的  .minecraft  文件夹里。\n\n' +
      '由于 .minecraft 以点(.)开头，文件管理器默认会把它当作“隐藏文件夹”而不显示。\n' +
      '这是 Linux/鸿蒙文件系统的命名约定，不是出了问题。\n\n' +
      '查看 / 管理这些文件的方法：\n' +
      '  打开文件管理器右上角菜单 → 开启“显示隐藏文件 / 显示隐藏项”\n' +
      '  即可看到本目录下的 .minecraft 文件夹及其中内容。\n\n' +
      `注意：${note}\n` +
      '此说明文件由 FCL 自动生成，可以删除。\n';
    try {
      fs.mkdirSync(dir, true);
    } catch (err) {
      hilog.debug(0x0000, TAG, `mkdir hint dir (may exist): ${err}`);
    }
    try {
      const f = fs.openSync(hintPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, content);
      } finally {
        fs.closeSync(f);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, `writeHint failed: ${err}`);
    }
  }
}
