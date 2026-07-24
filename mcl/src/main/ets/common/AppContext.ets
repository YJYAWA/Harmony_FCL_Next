/**
 * 全局应用上下文
 * 提供 Context 访问，替代 Android Context 模式
 */
import { common } from '@kit.AbilityKit';

export class AppContext {
  private static _context: common.Context | null = null;

  static init(context: common.Context): void {
    AppContext._context = context;
  }

  static get context(): common.Context {
    if (!AppContext._context) {
      throw new Error('AppContext not initialized. Call AppContext.init(context) first.');
    }
    return AppContext._context;
  }

  /** 获取应用沙箱文件目录 */
  static get filesDir(): string {
    return AppContext.context.filesDir;
  }

  /** 获取临时目录 */
  static get tempDir(): string {
    return AppContext.context.tempDir;
  }

  /** 获取缓存目录 */
  static get cacheDir(): string {
    return AppContext.context.cacheDir;
  }
}
