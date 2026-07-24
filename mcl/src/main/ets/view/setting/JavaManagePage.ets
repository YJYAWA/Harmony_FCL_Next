/**
 * Java 运行时管理页面
 * 移植自: FCL ui/dialog/JavaManageDialog + RendererSelectDialog
 *
 * 功能: 选择/导入/删除 JDK 版本，选择渲染器
 */
import { FileUtils } from '../../core/util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { SettingsManager } from '../../core/SettingsManager';
import { Architecture } from '../../core/util/Architecture';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-JavaManage';

/** Java 运行时条目 */
interface JavaRuntime {
  name: string;
  path: string;
  version: number;
  vendor: string;
  arch: string;
  sizeFormatted: string;
  isAutoDetected: boolean;
}

/** 渲染器类型 */
enum Renderer {
  AUTO = 'auto',
  VIRGL = 'virgl',
  ZINK = 'zink',
  MESA = 'mesa',
  GL4ES = 'gl4es'
}

@ComponentV2
export struct JavaManagePage {
  @Local javaRuntimes: JavaRuntime[] = [];
  @Local selectedJava: string = '';
  @Local selectedRenderer: Renderer = Renderer.AUTO;
  @Local showAddDialog: boolean = false;
  @Local searchPath: string = '';

  private settings: SettingsManager = SettingsManager.getInstance();

  aboutToAppear(): void {
    this.loadRuntimes();
    this.selectedJava = this.settings.get('javaPath') || 'Auto-detect';
  }

  loadRuntimes(): void {
    this.javaRuntimes = [];

    // 自动检测预置 JDK (AMCL 构建)
    const builtin = [
      { name: 'JDK 8 (Built-in)', path: `${AppContext.filesDir}/jdk/jdk8/bin/java`, version: 8, vendor: 'OpenJDK', arch: 'aarch64', sizeFormatted: '37MB', isAutoDetected: true },
      { name: 'JDK 17 (Built-in)', path: `${AppContext.filesDir}/jdk/jdk17/bin/java`, version: 17, vendor: 'OpenJDK', arch: 'aarch64', sizeFormatted: '108MB', isAutoDetected: true },
      { name: 'JDK 21 (Built-in)', path: `${AppContext.filesDir}/jdk/jdk21/bin/java`, version: 21, vendor: 'OpenJDK', arch: 'aarch64', sizeFormatted: '112MB', isAutoDetected: true }
    ];

    for (const rt of builtin) {
      if (FileUtils.exists(rt.path)) {
        this.javaRuntimes.push(rt);
      }
    }

    // 扫描自定义安装的 Java
    const jdkDir = `${AppContext.filesDir}/jdk`;
    if (FileUtils.exists(jdkDir)) {
      const dirs = FileUtils.listFiles(jdkDir);
      for (const d of dirs) {
        const javaPath = `${jdkDir}/${d}/bin/java`;
        if (FileUtils.exists(javaPath)) {
          this.javaRuntimes.push({
            name: d,
            path: javaPath,
            version: 0,
            vendor: 'Custom',
            arch: Architecture.getJDKArch(),
            sizeFormatted: '-',
            isAutoDetected: false
          });
        }
      }
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // Java 运行时列表
          this.buildSection('Java Runtime');
          Text('Select the Java version to run Minecraft')
            .fontSize(12).fontColor('#666666').margin({ bottom: 8 })

          ForEach(this.javaRuntimes, (rt: JavaRuntime) => {
            this.buildJavaCard(rt);
          })

          if (this.javaRuntimes.length === 0) {
            Text('No Java runtime found. Please download one.')
              .fontSize(14).fontColor('#999999').margin({ top: 32 })
              .width('100%').textAlign(TextAlign.Center)
          }

          // 导入按钮
          Button('Import JDK')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .margin({ top: 16 }).width('100%')
            .onClick(() => { this.showAddDialog = true; })

          // 渲染器选择
          this.buildSection('Renderer');
          Text('Select the OpenGL rendering backend')
            .fontSize(12).fontColor('#666666').margin({ bottom: 8 })

          ForEach(
            [
              { v: Renderer.AUTO, l: 'Auto-detect', d: 'Automatically select best renderer' },
              { v: Renderer.GL4ES, l: 'GL4ES', d: 'OpenGL→GLES translation (best compatibility)' },
              { v: Renderer.VIRGL, l: 'VirGL', d: 'Virtual GPU (best performance)' },
              { v: Renderer.ZINK, l: 'Zink', d: 'OpenGL over Vulkan (experimental)' }
            ],
            (item: { v: Renderer; l: string; d: string }) => {
              this.buildRendererCard(item.v, item.l, item.d);
            }
          )

          // 下载提示
          this.buildSection('Download JDK');
          Text('Recommended JDK builds for HarmonyOS NEXT:')
            .fontSize(12).fontColor('#666666').margin({ bottom: 8 })

          Column() {
            Text('AMCL OpenJDK Releases').fontSize(14).fontColor('#2196F3')
            Text('github.com/LZZLHY/mc-ohos-resources/releases').fontSize(11).fontColor('#666666').margin({ top: 2 })
            Text('Supports Java 8, 17, 21, 25 for HarmonyOS (musl, aarch64)').fontSize(11).fontColor('#555555').margin({ top: 4 })
          }
          .width('100%').padding(12).backgroundColor('#16213E').borderRadius(8)

          // 底部间距
          Column().height(32)
        }
        .width('100%').padding(16)
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')
    }
    .title('Java & Renderer')
  }

  @Builder
  buildSection(title: string) {
    Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E94560')
      .width('100%').margin({ top: 20, bottom: 8 })
  }

  @Builder
  buildJavaCard(rt: JavaRuntime) {
    Row() {
      Column() {
        Text(rt.name).fontSize(15).fontColor('#FFFFFF')
        Text(`v${rt.version} · ${rt.vendor} · ${rt.arch} · ${rt.sizeFormatted}`)
          .fontSize(11).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (this.selectedJava === rt.path) {
        Text('Selected ✓').fontSize(13).fontColor('#4CAF50')
      } else {
        Button('Select').fontSize(12).fontColor('#FFFFFF').backgroundColor('#E94560')
          .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.selectedJava = rt.path;
            this.settings.set('javaPath', rt.path);
            promptAction.showToast({ message: `Selected ${rt.name}` });
          })
      }
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(8)
    .margin({ bottom: 6 })
  }

  @Builder
  buildRendererCard(value: Renderer, label: string, desc: string) {
    Row() {
      Column() {
        Text(label).fontSize(15).fontColor(this.selectedRenderer === value ? '#4CAF50' : '#FFFFFF')
        Text(desc).fontSize(11).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Radio({ value, group: 'renderer' })
        .checked(this.selectedRenderer === value)
        .onChange((checked: boolean) => {
          if (checked) {
            this.selectedRenderer = value;
            hilog.info(0x0000, TAG, `Renderer selected: ${value}`);
          }
        })
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(8)
    .margin({ bottom: 6 })
  }
}
