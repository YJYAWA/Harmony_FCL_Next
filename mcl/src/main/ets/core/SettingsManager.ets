/**
 * FCL 启动器设置管理
 * 移植自: FCLCore + FCL/setting
 * 使用 HarmonyOS Preferences 替代 Android SharedPreferences
 */
import { preferences as dataPreferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';

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
  /** 渲染器：mobileglues(默认) / mobilegl(MC 26.3+) / gl4es / auto */
  renderer: string;

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
  renderer: string = 'mobileglues';
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
  renderer: 'mobileglues',

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
  private preferences: dataPreferences.Preferences | null = null;
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
    c.renderer = s.renderer;
    c.windowWidth = s.windowWidth; c.windowHeight = s.windowHeight; c.fullscreen = s.fullscreen;
    c.autoCloseLauncher = s.autoCloseLauncher; c.showLogs = s.showLogs; c.debugMode = s.debugMode;
    return c;
  }

  static mergeSettings(base: LauncherSettings, overrides: Partial<LauncherSettings>): LauncherSettings {
    const c = SettingsManager.cloneSettings(base);
    const o = overrides as Record<string, Object>;
    if (o['theme'] !== undefined) {
      c.theme = o['theme'] as Theme;
    }
    if (o['backgroundColor'] !== undefined) {
      c.backgroundColor = o['backgroundColor'] as string;
    }
    if (o['backgroundImagePath'] !== undefined) {
      c.backgroundImagePath = o['backgroundImagePath'] as string;
    }
    if (o['downloadSource'] !== undefined) {
      c.downloadSource = o['downloadSource'] as DownloadSource;
    }
    if (o['downloadConcurrency'] !== undefined) {
      c.downloadConcurrency = o['downloadConcurrency'] as number;
    }
    if (o['downloadThreads'] !== undefined) {
      c.downloadThreads = o['downloadThreads'] as number;
    }
    if (o['language'] !== undefined) {
      c.language = o['language'] as Language;
    }
    if (o['renderer'] !== undefined) {
      c.renderer = o['renderer'] as string;
    }
    if (o['maxMemory'] !== undefined) {
      c.maxMemory = o['maxMemory'] as number;
    }
    if (o['minMemory'] !== undefined) {
      c.minMemory = o['minMemory'] as number;
    }
    if (o['javaPath'] !== undefined) {
      c.javaPath = o['javaPath'] as string;
    }
    if (o['gameDir'] !== undefined) {
      c.gameDir = o['gameDir'] as string;
    }
    if (o['extraJVMArgs'] !== undefined) {
      c.extraJVMArgs = o['extraJVMArgs'] as string;
    }
    if (o['windowWidth'] !== undefined) {
      c.windowWidth = o['windowWidth'] as number;
    }
    if (o['windowHeight'] !== undefined) {
      c.windowHeight = o['windowHeight'] as number;
    }
    if (o['fullscreen'] !== undefined) {
      c.fullscreen = o['fullscreen'] as boolean;
    }
    if (o['autoCloseLauncher'] !== undefined) {
      c.autoCloseLauncher = o['autoCloseLauncher'] as boolean;
    }
    if (o['showLogs'] !== undefined) {
      c.showLogs = o['showLogs'] as boolean;
    }
    if (o['debugMode'] !== undefined) {
      c.debugMode = o['debugMode'] as boolean;
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
    const prefs = await dataPreferences.getPreferences(
      AppContext.context, 'fcl_settings'
    );
    this.preferences = prefs;

    // 从存储中读取
    const stored: dataPreferences.ValueType = await prefs.get('launcher_settings', '');
    if (stored && typeof stored === 'string' && (stored as string).length > 0) {
      try {
        const parsed = JSON.parse(stored as string) as Partial<LauncherSettings>;
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

  /** 设置单个设置项 (ArkTS 不支持泛型索引访问，key 用字符串，value 用 Object) */
  async set(key: string, value: Object): Promise<void> {
    await this.updateSettings(SettingsManager.buildPatch(key, value));
  }

  /** 按显式 switch 构造单项设置补丁 (替代计算属性名对象字面量) */
  private static buildPatch(key: string, value: Object): Partial<LauncherSettings> {
    const patch: Partial<LauncherSettings> = {};
    switch (key) {
      case 'theme':
        patch.theme = value as Theme;
        break;
      case 'backgroundColor':
        patch.backgroundColor = value as string;
        break;
      case 'backgroundImagePath':
        patch.backgroundImagePath = value as string;
        break;
      case 'downloadSource':
        patch.downloadSource = value as DownloadSource;
        break;
      case 'downloadConcurrency':
        patch.downloadConcurrency = value as number;
        break;
      case 'downloadThreads':
        patch.downloadThreads = value as number;
        break;
      case 'language':
        patch.language = value as Language;
        break;
      case 'maxMemory':
        patch.maxMemory = value as number;
        break;
      case 'minMemory':
        patch.minMemory = value as number;
        break;
      case 'javaPath':
        patch.javaPath = value as string;
        break;
      case 'gameDir':
        patch.gameDir = value as string;
        break;
      case 'extraJVMArgs':
        patch.extraJVMArgs = value as string;
        break;
      case 'renderer':
        patch.renderer = value as string;
        break;
      case 'windowWidth':
        patch.windowWidth = value as number;
        break;
      case 'windowHeight':
        patch.windowHeight = value as number;
        break;
      case 'fullscreen':
        patch.fullscreen = value as boolean;
        break;
      case 'autoCloseLauncher':
        patch.autoCloseLauncher = value as boolean;
        break;
      case 'showLogs':
        patch.showLogs = value as boolean;
        break;
      case 'debugMode':
        patch.debugMode = value as boolean;
        break;
      default:
        break;
    }
    return patch;
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
