/**
 * 游戏渲染页面
 *
 * 全屏 XComponent（SURFACE 类型）作为 MC 的渲染表面：
 * - native 侧由 AMCL 图形栈接管（libraryname: 'entry' → libentry.so 的
 *   OnSurfaceCreated / DispatchTouchEvent 回调，GLFW 兼容层 + MobileGlues/
 *   MobileGL 渲染器在 surface 创建后出图）
 * - ArkTS 侧叠加 TouchController 触控覆盖层（虚拟按键事件经
 *   libfcl_native.so 的 ring buffer 通道注入）
 * - 启动动作由调用方（MainPage 快速启动/版本详情）先经 GameLauncherService
 *   发起，再导航到本页；返回键触发 stopGame。
 *
 * 参考: AMCL McGamePage.ets（GPL-3.0）的 XComponent 声明方式。
 */
import { GameLauncherService } from '../../service/GameLauncherService';
import { TouchController } from '../control/TouchController';
import { NavigationService } from '../../common/NavigationRouter';

@ComponentV2
export struct GamePage {
  @Local isRunning: boolean = false;
  @Local exitCode: number | null = null;

  aboutToAppear(): void {
    const launcher = GameLauncherService.getInstance();
    this.isRunning = launcher.isGameRunningNative();
  }

  build() {
    Stack() {
      // MC 渲染区域：native 侧接管 surface 生命周期与触摸事件
      XComponent({
        id: 'mc_game_surface',
        type: XComponentType.SURFACE,
        libraryname: 'entry'
      })
        .width('100%')
        .height('100%')

      // 触控覆盖层（虚拟按键 / 方向键 / 触摸板）
      TouchController()

      // 顶部悬浮状态条
      if (this.exitCode !== null) {
        Column() {
          Text(`Game exited (code ${this.exitCode})`)
            .fontSize(14)
            .fontColor('#FFFFFF')
          Button('Back')
            .onClick(() => {
              NavigationService.pop();
            })
            .margin({ top: 12 })
        }
        .width('80%')
        .padding(20)
        .backgroundColor('rgba(0,0,0,0.8)')
        .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
