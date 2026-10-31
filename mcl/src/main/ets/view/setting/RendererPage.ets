/**
 * 渲染器选择页
 * 对齐原版 FCL / HarmonyFCL 的渲染器管理体验：卡片列表 + 描述 + 徽标 + 选中态，
 * 选择持久化到 SettingsManager（renderer 字段），启动时经
 * GameLauncherService → native.launchJVM(renderer) 激活 AMCL GraphicsPlan。
 */
import { SettingsManager, LauncherSettings } from '../../core/SettingsManager';
import { NavigationService, RouteNames } from '../../common/NavigationRouter';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-RendererPage';

/** 渲染器选项数据（类形式满足 arkts-no-untyped-obj-literals） */
class RendererOption {
  value: string = 'mobileglues';
  name: string = '';
  desc: string = '';
  badge: string = '';
  recommended: boolean = false;
  /** 是否提供齿轮入口（上游 FCL 1.3.4.3：内置渲染器行尾齿轮配置） */
  configurable: boolean = false;
}

function makeOptions(): Array<RendererOption> {
  const list: Array<RendererOption> = [];

  const auto = new RendererOption();
  auto.value = 'auto';
  auto.name = 'Auto-detect (自动选择)';
  auto.desc = '按游戏版本自动匹配最优渲染器（等同 MobileGlues 基线）';
  list.push(auto);

  const mg = new RendererOption();
  mg.value = 'mobileglues';
  mg.name = 'MobileGlues';
  mg.desc = 'OpenGL → GLES 翻译层。兼容性最好，AMCL 真机全链路验证（1.20.4）。需 NEED_OPENGL=1（已内置）。行尾齿轮可配置 MobileGlues 全量运行时选项';
  mg.badge = '推荐';
  mg.recommended = true;
  mg.configurable = true;
  list.push(mg);

  const mgl = new RendererOption();
  mgl.value = 'mobilegl';
  mgl.name = 'MobileGL';
  mgl.desc = 'DirectVulkan 渲染器（SDL3 窗口提供者 + 26.3 保守审计基线）。Minecraft 26.3+ 版本必须选择此项';
  mgl.badge = 'MC 26.3+ 必选';
  list.push(mgl);

  const gl4es = new RendererOption();
  gl4es.value = 'gl4es';
  gl4es.name = 'GL4ES';
  gl4es.desc = 'OpenGL → GLES 翻译（legacy 路径，LWJGL2 时代版本适用）';
  list.push(gl4es);

  // 上游 FCL 1.3.4.3：OSMesa 已从内置剥离为渲染器插件（不再随包内置），
  // VirGL / Freedreno 内置条目同样移除。Next 侧未实现对应插件，故不再列出，
  // 避免选择后被静默回退到 MobileGlues 基线。

  return list;
}

@ComponentV2
export struct RendererPage {
  @Local settings: LauncherSettings = SettingsManager.getInstance().settings;
  @Local selected: string = this.settings.renderer;
  private options: Array<RendererOption> = makeOptions();

  private async choose(value: string): Promise<void> {
    this.selected = value;
    // 持久化到 Preferences（SettingsManager.renderer 字段）
    await SettingsManager.getInstance().set('renderer', value);
    // 兼容旧通道：GameLauncherService 优先读持久化设置，AppStorage 作即时回退
    AppStorage.setOrCreate('fcl.renderer', value);
    hilog.info(0x0000, TAG, `Renderer selected: ${value}`);
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20).fontColor('#FFFFFF')
          .onClick(() => {
            NavigationService.pop();
          })
          .padding({ right: 12 })

        Text('渲染器')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 4 })

        Text('选择游戏使用的图形渲染后端。选择即时保存，下次启动游戏生效。')
          .fontSize(12).fontColor('#8899AA')
          .width('100%').padding({ left: 16, bottom: 12 })

        List({ space: 10 }) {
          ForEach(this.options, (opt: RendererOption) => {
            ListItem() {
              Row() {
                Column() {
                  Row() {
                    Text(opt.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.selected === opt.value ? '#4CAF50' : '#FFFFFF')
                    if (opt.badge.length > 0) {
                      Text(opt.badge)
                        .fontSize(10)
                        .fontColor(opt.recommended ? '#4CAF50' : '#FF9800')
                        .border({ width: 1, color: opt.recommended ? '#4CAF50' : '#FF9800' })
                        .borderRadius(4)
                        .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                        .margin({ left: 8 })
                    }
                  }

                  Text(opt.desc)
                    .fontSize(12)
                    .fontColor('#8899AA')
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Radio({ value: opt.value, group: 'renderer' })
                  .checked(this.selected === opt.value)
                  .onChange((checked: boolean) => {
                    if (checked) {
                      this.choose(opt.value);
                    }
                  })
                  .radioStyle({ checkedBackgroundColor: '#4CAF50' })

                if (opt.configurable) {
                  Text('⚙')
                    .fontSize(18)
                    .fontColor('#8899AA')
                    .padding({ left: 12 })
                    .onClick(() => {
                      NavigationService.push(RouteNames.MG_OPTIONS);
                    })
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(10)
              .backgroundColor(this.selected === opt.value ? 'rgba(76,175,80,0.12)' : '#16213E')
              .border({ width: 1, color: this.selected === opt.value ? '#4CAF50' : '#22335C' })
              .onClick(() => {
                this.choose(opt.value);
              })
            }
          }, (opt: RendererOption) => opt.value)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })

        Button('完成')
          .width('60%')
          .backgroundColor('#E94560')
          .margin({ bottom: 16 })
          .onClick(() => {
            NavigationService.pop();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#0F1629')
  }
}
