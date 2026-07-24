/**
 * 主页面 ViewModel (MVVM 模式)
 * 使用 V2 状态管理装饰器
 */
import { Preferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';

@ObservedV2
export class MainViewModel {
  @Trace selectedTabIndex: number = 0;
  @Trace isInitialized: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace statusMessage: string = '';

  private preferences: Preferences | null = null;
  private onDisposeCallbacks: Array<() => void> = [];

  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    this.isLoading = true;
    this.statusMessage = '正在初始化...';

    try {
      // 加载首选项
      this.preferences = await Preferences.getPreferences(
        AppContext.context, 'fcl_settings'
      );

      // 恢复上次选择
      const lastTab = await this.preferences.get('last_tab', 0) as number;
      this.selectedTabIndex = lastTab;

      this.isInitialized = true;
      this.statusMessage = '就绪';
    } catch (err) {
      this.statusMessage = `初始化失败: ${err}`;
    } finally {
      this.isLoading = false;
    }
  }

  selectTab(index: number): void {
    this.selectedTabIndex = index;
    // 保存选择
    if (this.preferences) {
      this.preferences.put('last_tab', index);
    }
  }

  /**
   * 注册清理回调
   */
  addDisposeCallback(callback: () => void): void {
    this.onDisposeCallbacks.push(callback);
  }

  /**
   * 释放资源
   */
  dispose(): void {
    this.onDisposeCallbacks.forEach(cb => {
      try {
        cb();
      } catch (err) {
        // 忽略清理错误
      }
    });
    this.onDisposeCallbacks = [];

    if (this.preferences) {
      this.preferences.flush();
    }
  }
}
