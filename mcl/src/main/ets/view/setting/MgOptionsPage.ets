/**
 * MobileGlues 运行时选项页
 *
 * 同步上游 FCL 1.3.4.3「内置 MobileGlues 渲染器 + 行尾齿轮入口配置」：
 * 上游为内置渲染器列表行尾新增齿轮入口，支持配置环境变量与 MobileGlues
 * 全量运行时选项，启动时把显式配置过的键合并写入 files/mobileglues/config.json
 * （保留 MG 自管键）经 MG_DIR_PATH 生效。
 *
 * 本移植版对应落点：写入 <filesDir>/MG/config.json，与原生层 MG_DIR_PATH 一致。
 */
import { MgOptions, MgOptionMeta } from '../../core/util/MgOptions';
import { AppContext } from '../../common/AppContext';
import { NavigationService } from '../../common/NavigationRouter';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-MgOptionsPage';

@ComponentV2
export struct MgOptionsPage {
  @Local overrides: Map<string, number> = new Map<string, number>();
  @Local filesDir: string = '';

  aboutToAppear(): void {
    try {
      this.filesDir = AppContext.filesDir;
      this.overrides = MgOptions.readOverrides(this.filesDir);
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to read MG config: ${err}`);
      this.filesDir = '';
      this.overrides = new Map<string, number>();
    }
  }

  private currentValue(meta: MgOptionMeta): number {
    const value = this.overrides.get(meta.key);
    return typeof value === 'number' ? value : -1;
  }

  private setValue(meta: MgOptionMeta, value: number): void {
    const next: Map<string, number> = new Map<string, number>();
    this.overrides.forEach((existing: number, key: string) => {
      next.set(key, existing);
    });
    next.set(meta.key, value);
    this.overrides = next;
    if (this.filesDir.length > 0) {
      MgOptions.writeOverrides(this.filesDir, next);
    }
  }

  private resetAll(): void {
    if (this.filesDir.length > 0) {
      MgOptions.clearOverrides(this.filesDir);
    }
    this.overrides = new Map<string, number>();
    hilog.info(0x0000, TAG, 'MG overrides cleared');
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20).fontColor('#FFFFFF')
          .onClick(() => { NavigationService.pop(); })
          .padding({ right: 12 })
        Text('MobileGlues 选项')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 4 })

      Text('与上游 FCL 1.3.4.3 一致：仅显式配置过的键会合并写入 config.json，未配置的键保持 MobileGlues 自身默认值。')
        .fontSize(12).fontColor('#8899AA')
        .width('100%').padding({ left: 16, right: 16, bottom: 12 })

      List({ space: 10 }) {
        ForEach(MgOptions.METAS, (meta: MgOptionMeta) => {
          ListItem() {
            Column() {
              Text(meta.label)
                .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              Text(meta.desc)
                .fontSize(12).fontColor('#8899AA').margin({ top: 4 })
              Row({ space: 8 }) {
                ForEach(meta.values, (value: number) => {
                  Text(`${value}`)
                    .fontSize(13)
                    .fontColor(this.currentValue(meta) === value ? '#4CAF50' : '#8899AA')
                    .border({ width: 1, color: this.currentValue(meta) === value ? '#4CAF50' : '#22335C' })
                    .borderRadius(6)
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .onClick(() => { this.setValue(meta, value); })
                }, (value: number) => `${meta.key}-${value}`)
              }
              .margin({ top: 10 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(14)
            .borderRadius(10)
            .backgroundColor('#16213E')
            .border({ width: 1, color: '#22335C' })
          }
        }, (meta: MgOptionMeta) => meta.key)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })

      Button('恢复默认')
        .width('60%')
        .backgroundColor('#E94560')
        .margin({ bottom: 16 })
        .onClick(() => { this.resetAll(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0F1629')
  }
}
