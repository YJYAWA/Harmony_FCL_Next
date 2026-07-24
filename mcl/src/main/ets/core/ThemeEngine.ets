/**
 * 主题引擎
 * 移植自: FCLLibrary/skin/ + FCL 主题系统
 *
 * 支持:
 * - 深色/浅色/跟随系统 三模式
 * - 自定义背景图片
 * - 强调色方案
 * - UI 缩放
 */
import { Preferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';
import { Theme } from './SettingsManager';

/** 强调色方案 */
export enum AccentColor {
  RED = '#E94560',
  BLUE = '#2196F3',
  GREEN = '#4CAF50',
  PURPLE = '#9C27B0',
  ORANGE = '#FF9800',
  TEAL = '#009688',
  PINK = '#E91E63',
  CYAN = '#00BCD4'
}

/** 主题配置 */
export interface ThemeConfig {
  mode: Theme;
  accentColor: string;
  backgroundImage: string;
  backgroundOpacity: number;
  uiScale: number;
  blurEnabled: boolean;
  animationSpeed: 'fast' | 'normal' | 'slow';
}

/** 默认主题 */
const DEFAULT_THEME: ThemeConfig = {
  mode: Theme.DARK,
  accentColor: AccentColor.RED,
  backgroundImage: '',
  backgroundOpacity: 0.15,
  uiScale: 1.0,
  blurEnabled: true,
  animationSpeed: 'normal'
};

/** 深色主题色板 */
export const DarkPalette = {
  background: '#1A1A2E',
  surface: '#16213E',
  surfaceVariant: '#0F3460',
  surfaceLight: '#1E3A5F',
  text: '#FFFFFF',
  textSecondary: '#CCCCCC',
  textTertiary: '#999999',
  textDisabled: '#666666',
  border: '#2A2A4A',
  divider: '#0D1B2A',
  error: '#FF5252',
  success: '#4CAF50',
  warning: '#FF9800',
  info: '#2196F3'
};

/** 浅色主题色板 */
export const LightPalette = {
  background: '#F5F5F5',
  surface: '#FFFFFF',
  surfaceVariant: '#E8E8E8',
  surfaceLight: '#F0F0F0',
  text: '#1A1A1A',
  textSecondary: '#333333',
  textTertiary: '#666666',
  textDisabled: '#999999',
  border: '#DDDDDD',
  divider: '#EEEEEE',
  error: '#D32F2F',
  success: '#388E3C',
  warning: '#F57C00',
  info: '#1976D2'
};

/**
 * 主题引擎 (单例)
 */
export class ThemeEngine {
  private static instance: ThemeEngine | null = null;
  private config: ThemeConfig = { ...DEFAULT_THEME };
  private preferences: Preferences | null = null;
  private listeners: Array<(config: ThemeConfig) => void> = [];

  private constructor() {
  }

  static getInstance(): ThemeEngine {
    if (!ThemeEngine.instance) {
      ThemeEngine.instance = new ThemeEngine();
    }
    return ThemeEngine.instance;
  }

  get themeConfig(): ThemeConfig {
    return { ...this.config };
  }

  /** 获取当前色板 */
  get palette(): Record<string, string> {
    return this.config.mode === Theme.LIGHT ? LightPalette : DarkPalette;
  }

  /** 获取实际模式 (考虑 SYSTEM) */
  get effectiveMode(): Theme.LIGHT | Theme.DARK {
    if (this.config.mode === Theme.SYSTEM) {
      // 检查系统深色模式设置
      try {
        // TODO: 通过系统 API 获取 isDarkMode
        return Theme.DARK;
      } catch {
        return Theme.DARK;
      }
    }
    return this.config.mode === Theme.LIGHT ? Theme.LIGHT : Theme.DARK;
  }

  async initialize(): Promise<void> {
    this.preferences = await Preferences.getPreferences(
      AppContext.context, 'fcl_theme'
    );

    const stored = await this.preferences.get('theme_config', '');
    if (stored && typeof stored === 'string' && stored.length > 0) {
      try {
        const parsed = JSON.parse(stored) as Partial<ThemeConfig>;
        this.config = { ...DEFAULT_THEME, ...parsed };
      } catch {
        this.config = { ...DEFAULT_THEME };
      }
    }
  }

  async updateConfig(patch: Partial<ThemeConfig>): Promise<void> {
    this.config = { ...this.config, ...patch };

    if (this.preferences) {
      await this.preferences.put('theme_config', JSON.stringify(this.config));
      await this.preferences.flush();
    }

    this.notifyListeners();
  }

  async setMode(mode: Theme): Promise<void> {
    await this.updateConfig({ mode });
  }

  async setAccentColor(color: string): Promise<void> {
    await this.updateConfig({ accentColor: color });
  }

  async setBackgroundImage(path: string): Promise<void> {
    await this.updateConfig({ backgroundImage: path });
  }

  async setUIScale(scale: number): Promise<void> {
    await this.updateConfig({ uiScale: Math.max(0.75, Math.min(1.5, scale)) });
  }

  /** 获取动画时长 (毫秒) */
  getAnimationDuration(): number {
    switch (this.config.animationSpeed) {
      case 'fast': return 150;
      case 'slow': return 500;
      default: return 300;
    }
  }

  /** 获取动画曲线 */
  getAnimationCurve(): Curve {
    return Curve.EaseInOut;
  }

  addListener(listener: (config: ThemeConfig) => void): void {
    this.listeners.push(listener);
  }

  removeListener(listener: (config: ThemeConfig) => void): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyListeners(): void {
    const snapshot = this.themeConfig;
    this.listeners.forEach(l => {
      try { l(snapshot); } catch { /* ignore */ }
    });
  }
}
