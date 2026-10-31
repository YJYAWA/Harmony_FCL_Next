/**
 * 存储位置设置管理
 *
 * 配合 core/storage/GameStorage.ets 使用：
 * 持久化用户选择的「游戏数据位置」（沙箱内 / 沙箱外），并在切换时做数据迁移。
 *
 * 鸿蒙权限要点（对齐 AMCL）：
 * - READ_WRITE_DOWNLOAD_DIRECTORY 是 user_grant 权限，**必须在运行时申请**，
 *   仅在 module.json5 声明不够；
 * - 手机端 getUserDownloadDir 不可用（报 801），改用 DocumentViewPicker 学路径，
 *   学到的目录走所有权式访问，跨重启有效，无需 persist/activate。
 */
import { preferences as dataPreferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../../common/AppContext';
import { GameStorage, StorageLocation, parseStorageLocation } from '../storage/GameStorage';

const TAG = 'FCL-StorageManager';
const PREFS_NAME = 'fcl_storage';
const KEY_LOCATION = 'storage_location';
const KEY_PHONE_DIR = 'phone_external_dir';

export class StorageManager {
  private static instance: StorageManager | null = null;

  private _location: StorageLocation = StorageLocation.SANDBOX;
  private prefs: dataPreferences.Preferences | null = null;

  private constructor() {
  }

  static getInstance(): StorageManager {
    if (!StorageManager.instance) {
      StorageManager.instance = new StorageManager();
    }
    return StorageManager.instance;
  }

  /** 加载持久化的存储位置 */
  async initialize(): Promise<void> {
    try {
      this.prefs = await dataPreferences.getPreferences(AppContext.context, PREFS_NAME);
      const stored = await this.prefs.get(KEY_LOCATION, '');
      if (typeof stored === 'string' && stored.length > 0) {
        this._location = parseStorageLocation(stored);
      }
      const phoneDir = await this.prefs.get(KEY_PHONE_DIR, '');
      if (typeof phoneDir === 'string' && phoneDir.length > 0) {
        GameStorage.setPhoneExternalDir(phoneDir);
      }
      hilog.info(0x0000, TAG, `storage location: ${this._location}`);
    } catch (err) {
      hilog.warn(0x0000, TAG, `initialize failed: ${err}`);
    }
    GameStorage.writeHints();
  }

  get storageLocation(): StorageLocation {
    return this._location;
  }

  /** 外部存储在本设备是否已就绪 */
  isExternalAvailable(): boolean {
    return GameStorage.isExternalAvailable();
  }

  /** 外部存储在本设备是否可启用 */
  isExternalSupported(): boolean {
    return GameStorage.isExternalSupported();
  }

  /**
   * 切换存储位置
   *
   * 切到 EXTERNAL 时：
   * 1. 平板 → 运行时申请 READ_WRITE_DOWNLOAD_DIRECTORY（user_grant 必须申请）
   * 2. 手机 → DocumentViewPicker 学一次公共应用目录路径
   * 3. 把沙箱内的现有游戏数据复制过去（源保留不删）
   */
  async setStorageLocation(location: StorageLocation): Promise<boolean> {
    if (location === StorageLocation.EXTERNAL) {
      if (!GameStorage.isExternalSupported()) {
        hilog.warn(0x0000, TAG, 'external storage not supported on this device');
        return false;
      }

      if (GameStorage.needsPhoneLearn()) {
        const learned = await GameStorage.ensurePhoneExternalDir();
        if (learned.length === 0) {
          hilog.warn(0x0000, TAG, 'user cancelled external dir picker');
          return false;
        }
        await this.persistPhoneDir(learned);
      } else if (!GameStorage.isDownloadPermissionGranted()) {
        // 平板路线：必须运行时申请 READ_WRITE_DOWNLOAD_DIRECTORY
        const granted = await GameStorage.requestDownloadPermission();
        if (!granted) {
          hilog.warn(0x0000, TAG, 'READ_WRITE_DOWNLOAD_DIRECTORY not granted');
          return false;
        }
      }
    }

    const oldDir = GameStorage.resolveMcDir(this._location);
    const newDir = GameStorage.resolveMcDir(location);
    if (oldDir !== newDir && GameStorage.hasVersions(oldDir)) {
      hilog.info(0x0000, TAG, `migrating game data ${oldDir} -> ${newDir}`);
      await GameStorage.migrate(oldDir, newDir);
    }

    this._location = location;
    if (this.prefs) {
      await this.prefs.put(KEY_LOCATION, location);
      await this.prefs.flush();
    }
    GameStorage.writeHints();
    hilog.info(0x0000, TAG, `storage location set to ${location}`);
    return true;
  }

  private async persistPhoneDir(dir: string): Promise<void> {
    if (!this.prefs) {
      return;
    }
    try {
      await this.prefs.put(KEY_PHONE_DIR, dir);
      await this.prefs.flush();
    } catch (err) {
      hilog.warn(0x0000, TAG, `persistPhoneDir failed: ${err}`);
    }
  }
}
