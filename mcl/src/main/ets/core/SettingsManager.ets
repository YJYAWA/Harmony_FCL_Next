/**
 * FCL 启动器设置管理
 * 移植自: FCLCore + FCL/setting
 * 使用 HarmonyOS Preferences 替代 Android SharedPreferences
 */
import { Preferences } from '@kit.ArkData';
import { AppContext } from '../../common/AppContext';

/** 主题设置 */
export enum Theme {
  LIGHT = 'light',
  DARK = 'dark',
  SYSTEM = 'system'
}

/** 下载源设置 */
export enum DownloadSource {
  OFFICIAL = 'official',
  BMCLAPI = 'bmclapi',
  MCBBS = 'mcbbs'
}

/** 语言设置 */
export enum Language {
  AUTO = 'auto',
  ZH_CN = 'zh_CN',
  EN_US = 'en_US',
  RU_RU = 'ru_RU'
}

/** 启动器设置 */
export interface LauncherSettings {
  // 外观
  theme: Theme;
  backgroundColor: string;
  backgroundImagePath: string;

  // 下载
  downloadSource: DownloadSource;
  downloadConcurrency: number;
  downloadThreads: number;

  // 语言
  language: Language;

  // 游戏
  maxMemory: number;
  minMemory: number;
  javaPath: string;
  gameDir: string;
  extraJVMArgs: string;

  // 窗口
  windowWidth: number;
  windowHeight: number;
  fullscreen: boolean;

  // 启动后
  autoCloseLauncher: boolean;
  showLogs: boolean;

  // 调试
  debugMode: boolean;
}

/** Settings 数据类 (解决 arkts-no-obj-literals-as-types) */
class SettingsData implements LauncherSettings {
  theme: Theme = Theme.DARK;
  backgroundColor: string = '#1A1A2E';
  backgroundImagePath: string = '';
  downloadSource: DownloadSource = DownloadSource.BMCLAPI;
  downloadConcurrency: number = 8;
  downloadThreads: number = 4;
  language: Language = Language.AUTO;
  maxMemory: number = 4096;
  minMemory: number = 512;
  javaPath: string = '';
  gameDir: string = '';
  extraJVMArgs: string = '';
  windowWidth: number = 854;
  windowHeight: number = 480;
  fullscreen: boolean = false;
  autoCloseLauncher: boolean = false;
  showLogs: boolean = true;
  debugMode: boolean = false;
}

/** 默认设置 */
const DEFAULT_SETTINGS: LauncherSettings = {
  theme: Theme.DARK,
  backgroundColor: '#1A1A2E',
  backgroundImagePath: '',

  downloadSource: DownloadSource.BMCLAPI,
  downloadConcurrency: 8,
  downloadThreads: 4,

  language: Language.AUTO,

  maxMemory: 4096,
  minMemory: 512,
  javaPath: '',
  gameDir: '',
  extraJVMArgs: '',

  windowWidth: 854,
  windowHeight: 480,
  fullscreen: false,

  autoCloseLauncher: false,
  showLogs: true,

  debugMode: false
};

/**
 * 设置管理器
 * 单例模式
 */
export class SettingsManager {
  private static instance: SettingsManager | null = null;
  private preferences: Preferences | null = null;
  private _settings: LauncherSettings = SettingsManager.cloneSettings(DEFAULT_SETTINGS);
  private listeners: Array<(settings: LauncherSettings) => void> = [];

  private constructor() {
  }

  static cloneSettings(s: LauncherSettings): LauncherSettings {
    const c = new SettingsData();
    c.theme = s.theme; c.backgroundColor = s.backgroundColor; c.backgroundImagePath = s.backgroundImagePath;
    c.downloadSource = s.downloadSource; c.downloadConcurrency = s.downloadConcurrency; c.downloadThreads = s.downloadThreads;
    c.language = s.language; c.maxMemory = s.maxMemory; c.minMemory = s.minMemory;
    c.javaPath = s.javaPath; c.gameDir = s.gameDir; c.extraJVMArgs = s.extraJVMArgs;
    c.windowWidth = s.windowWidth; c.windowHeight = s.windowHeight; c.fullscreen = s.fullscreen;
    c.autoCloseLauncher = s.autoCloseLauncher; c.showLogs = s.showLogs; c.debugMode = s.debugMode;
    return c;
  }

  static mergeSettings(base: LauncherSettings, overrides: Partial<LauncherSettings>): LauncherSettings {
    const c = SettingsManager.cloneSettings(base);
    const o = overrides as Record<string, Object>;
    const keys: string[] = ['theme','backgroundColor','backgroundImagePath','downloadSource','downloadConcurrency','downloadThreads','language','maxMemory','minMemory','javaPath','gameDir','extraJVMArgs','windowWidth','windowHeight','fullscreen','autoCloseLauncher','showLogs','debugMode'];
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (o[k] !== undefined) {
        (c as Record<string, Object>)[k] = o[k];
      }
    }
    return c;
  }

  static getInstance(): SettingsManager {
    if (!SettingsManager.instance) {
      SettingsManager.instance = new SettingsManager();
    }
    return SettingsManager.instance;
  }

  get settings(): LauncherSettings {
    return SettingsManager.cloneSettings(this._settings);
  }

  /** 初始化并加载设置 */
  async initialize(): Promise<void> {
    this.preferences = await Preferences.getPreferences(
      AppContext.context, 'fcl_settings'
    );

    // 从存储中读取
    const stored = await this.preferences.get('launcher_settings', '');
    if (stored && typeof stored === 'string' && stored.length > 0) {
      try {
        const parsed = JSON.parse(stored) as Partial<LauncherSettings>;
        this._settings = SettingsManager.mergeSettings(DEFAULT_SETTINGS, parsed);
      } catch {
        this._settings = SettingsManager.cloneSettings(DEFAULT_SETTINGS);
      }
    }
  }

  /** 更新设置 */
  async updateSettings(patch: Partial<LauncherSettings>): Promise<void> {
    this._settings = SettingsManager.mergeSettings(this._settings, patch);

    // 持久化
    if (this.preferences) {
      await this.preferences.put('launcher_settings', JSON.stringify(this._settings));
      await this.preferences.flush();
    }

    // 通知监听器
    this.notifyListeners();
  }

  /** 重置为默认设置 */
  async resetToDefaults(): Promise<void> {
    this._settings = SettingsManager.cloneSettings(DEFAULT_SETTINGS);
    if (this.preferences) {
      await this.preferences.put('launcher_settings', JSON.stringify(this._settings));
      await this.preferences.flush();
    }
    this.notifyListeners();
  }

  /** 获取单个设置项 */
  get<K extends keyof LauncherSettings>(key: K): LauncherSettings[K] {
    return this._settings[key];
  }

  /** 设置单个设置项 */
  async set<K extends keyof LauncherSettings>(key: K, value: LauncherSettings[K]): Promise<void> {
    await this.updateSettings({ [key]: value } as Partial<LauncherSettings>);
  }

  /** 注册设置变更监听 */
  addListener(listener: (settings: LauncherSettings) => void): void {
    this.listeners.push(listener);
  }

  /** 移除设置变更监听 */
  removeListener(listener: (settings: LauncherSettings) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private notifyListeners(): void {
    const snapshot = this.settings;
    this.listeners.forEach(l => {
      try {
        l(snapshot);
      } catch {
        // 忽略监听器错误
      }
    });
  }
}
