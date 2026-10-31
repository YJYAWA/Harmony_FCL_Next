/**
 * 设置页面
 * 移植自: FCL/ui/setting/ + FCL/setting/
 */
import { SettingsManager, LauncherSettings, Theme, DownloadSource }
  from '../../core/SettingsManager';
import { StorageManager } from '../../core/storage/StorageManager';
import { StorageLocation } from '../../core/storage/GameStorage';
import { promptAction } from '@kit.ArkUI';

@ComponentV2
export struct SettingsPage {
  @Local settings: LauncherSettings = SettingsManager.getInstance().settings;
  @Local storageLocation: StorageLocation = StorageManager.getInstance().storageLocation;
  @Local storageBusy: boolean = false;
  private manager: SettingsManager = SettingsManager.getInstance();
  private storage: StorageManager = StorageManager.getInstance();

  aboutToAppear(): void {
    this.settings = this.manager.settings;
    this.storageLocation = this.storage.storageLocation;
  }

  build() {
    Scroll() {
      Column() {
        // 外观设置
        this.buildSection('Appearance');
        this.buildThemeSelector();
        this.buildBackgroundColorPicker();

        // 下载设置
        this.buildSection('Downloads');
        this.buildDownloadSourceSelector();
        this.buildSlider('Concurrent downloads', this.settings.downloadConcurrency, 1, 32, 1,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.downloadConcurrency = value;
            this.settings = s;
            this.manager.set('downloadConcurrency', value);
          });
        this.buildSlider('Download threads', this.settings.downloadThreads, 1, 16, 1,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.downloadThreads = value;
            this.settings = s;
            this.manager.set('downloadThreads', value);
          });

        // 游戏设置
        this.buildSection('Game');
        this.buildSlider('Min Memory (MB)', this.settings.minMemory, 256, 16384, 256,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.minMemory = value;
            this.settings = s;
            this.manager.set('minMemory', value);
          });
        this.buildSlider('Max Memory (MB)', this.settings.maxMemory, 512, 32768, 512,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.maxMemory = value;
            this.settings = s;
            this.manager.set('maxMemory', value);
          });
        this.buildInputField('Java Path', this.settings.javaPath,
          (value: string) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.javaPath = value;
            this.settings = s;
            this.manager.set('javaPath', value);
          });
        this.buildInputField('Extra JVM Args', this.settings.extraJVMArgs,
          (value: string) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.extraJVMArgs = value;
            this.settings = s;
            this.manager.set('extraJVMArgs', value);
          });

        // 游戏数据位置（鸿蒙沙箱严格：沙箱内卸载即丢）
        this.buildSection('Storage');
        this.buildStorageSelector();

        // 窗口设置
        this.buildSection('Window');
        this.buildToggle('Fullscreen', this.settings.fullscreen,
          (value: boolean) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.fullscreen = value;
            this.settings = s;
            this.manager.set('fullscreen', value);
          });
        this.buildSlider('Window Width', this.settings.windowWidth, 640, 3840, 1,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.windowWidth = value;
            this.settings = s;
            this.manager.set('windowWidth', value);
          });
        this.buildSlider('Window Height', this.settings.windowHeight, 480, 2160, 1,
          (value: number) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.windowHeight = value;
            this.settings = s;
            this.manager.set('windowHeight', value);
          });

        // 启动设置
        this.buildSection('Launch');
        this.buildToggle('Auto close launcher', this.settings.autoCloseLauncher,
          (value: boolean) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.autoCloseLauncher = value;
            this.settings = s;
            this.manager.set('autoCloseLauncher', value);
          });
        this.buildToggle('Show game logs', this.settings.showLogs,
          (value: boolean) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.showLogs = value;
            this.settings = s;
            this.manager.set('showLogs', value);
          });

        // 调试
        this.buildSection('Debug');
        this.buildToggle('Debug mode', this.settings.debugMode,
          (value: boolean) => {
            const s = SettingsManager.cloneSettings(this.settings);
            s.debugMode = value;
            this.settings = s;
            this.manager.set('debugMode', value);
          });

        // 重置按钮
        Button('Reset to Defaults')
          .fontSize(16)
          .fontColor('#FF5252')
          .backgroundColor('transparent')
          .border({ width: 1, color: '#FF5252' })
          .borderRadius(8)
          .padding(16)
          .margin({ top: 24, bottom: 32 })
          .width('100%')
          .onClick(async () => {
            await this.manager.resetToDefaults();
            this.settings = this.manager.settings;
            promptAction.showToast({ message: 'Settings reset to defaults' });
          });
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  buildSection(title: string) {
    Text(title)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor('#E94560')
      .width('100%')
      .margin({ top: 20, bottom: 12 })
  }

  @Builder
  buildThemeSelector() {
    Row() {
      Text('Theme')
        .fontSize(15)
        .fontColor('#CCCCCC')
        .layoutWeight(1)

      Row() {
        ForEach(
          [Theme.DARK, Theme.LIGHT, Theme.SYSTEM],
          (theme: Theme) => {
            Button(theme)
              .fontSize(12)
              .fontColor(this.settings.theme === theme ? '#FFFFFF' : '#999999')
              .backgroundColor(this.settings.theme === theme ? '#E94560' : '#0F3460')
              .borderRadius(6)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ left: 4 })
              .onClick(() => {
                const s = SettingsManager.cloneSettings(this.settings);
                s.theme = theme;
                this.settings = s;
                this.manager.set('theme', theme);
              })
          }
        )
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  buildDownloadSourceSelector() {
    Row() {
      Text('Download Source')
        .fontSize(15)
        .fontColor('#CCCCCC')
        .layoutWeight(1)

      Select([{ value: 'bmclapi' }, { value: 'official' }, { value: 'mcbbs' }])
        .value(this.settings.downloadSource)
        .font({ size: 14 })
        .selected(this.settings.downloadSource === 'bmclapi' ? 0 :
          this.settings.downloadSource === 'official' ? 1 : 2)
        .onSelect((index: number) => {
          const sources: DownloadSource[] = [DownloadSource.BMCLAPI, DownloadSource.OFFICIAL, DownloadSource.MCBBS];
          const s = SettingsManager.cloneSettings(this.settings);
          s.downloadSource = sources[index];
          this.settings = s;
          this.manager.set('downloadSource', sources[index]);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  buildBackgroundColorPicker() {
    Row() {
      Text('Background Color')
        .fontSize(15)
        .fontColor('#CCCCCC')

      Blank()

      // 预设颜色
      ForEach(['#1A1A2E', '#16213E', '#0F3460', '#533483', '#E94560', '#1A1A1A', '#FFFFFF'],
        (color: string) => {
          Row()
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(color)
            .border({
              width: this.settings.backgroundColor === color ? 2 : 0,
              color: '#E94560'
            })
            .margin({ left: 6 })
            .onClick(() => {
              const s = SettingsManager.cloneSettings(this.settings);
              s.backgroundColor = color;
              this.settings = s;
              this.manager.set('backgroundColor', color);
            })
        }
      )
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  /**
   * 游戏数据位置选择器
   *
   * 沙箱内：filesDir/.minecraft —— 卸载应用即删除
   * 沙箱外：Download/com.harmony.fcl/.minecraft —— 卸载不丢
   *
   * 切到沙箱外时会：平板走运行时申请 READ_WRITE_DOWNLOAD_DIRECTORY，
   * 手机走 DocumentViewPicker 学一次公共目录路径；并把已有游戏数据复制过去。
   */
  @Builder
  buildStorageSelector() {
    Column() {
      Row() {
        Column() {
          Text('Game data location')
            .fontSize(15).fontColor('#CCCCCC')
          Text(this.storageLocation === StorageLocation.EXTERNAL
            ? 'Download/com.harmony.fcl/.minecraft (survives uninstall)'
            : 'App sandbox (deleted on uninstall)')
            .fontSize(11).fontColor('#666666').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)

        if (this.storageBusy) {
          LoadingProgress().width(20).height(20).color('#E94560')
        } else {
          Row() {
            Button(this.storageLocation === StorageLocation.SANDBOX ? 'Sandbox' : 'External')
              .fontSize(12)
              .fontColor(this.storageLocation === StorageLocation.SANDBOX ? '#FFFFFF' : '#999999')
              .backgroundColor(this.storageLocation === StorageLocation.SANDBOX ? '#E94560' : '#0F3460')
              .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 6 })
              .onClick(() => this.changeStorage(StorageLocation.SANDBOX))
            Button(this.storageLocation === StorageLocation.EXTERNAL ? 'External' : 'External')
              .fontSize(12)
              .fontColor(this.storageLocation === StorageLocation.EXTERNAL ? '#FFFFFF' : '#999999')
              .backgroundColor(this.storageLocation === StorageLocation.EXTERNAL ? '#E94560' : '#0F3460')
              .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => this.changeStorage(StorageLocation.EXTERNAL))
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  async changeStorage(location: StorageLocation): Promise<void> {
    if (location === this.storageLocation) {
      return;
    }
    this.storageBusy = true;
    try {
      const ok = await this.storage.setStorageLocation(location);
      if (ok) {
        this.storageLocation = this.storage.storageLocation;
        promptAction.showToast({
          message: location === StorageLocation.EXTERNAL
            ? 'Switched to external storage'
            : 'Switched to app sandbox'
        });
      } else {
        promptAction.showToast({ message: 'Failed to switch storage location' });
      }
    } catch (err) {
      promptAction.showToast({ message: `Storage switch failed: ${err}` });
    } finally {
      this.storageBusy = false;
    }
  }

  @Builder
  buildToggle(label: string, value: boolean, onChange: (value: boolean) => void) {    Row() {
      Text(label)
        .fontSize(15)
        .fontColor('#CCCCCC')
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChange)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  buildSlider(label: string, value: number, min: number, max: number, step: number,
    onChange: (value: number) => void) {
    Column() {
      Row() {
        Text(label)
          .fontSize(15)
          .fontColor('#CCCCCC')
          .layoutWeight(1)
        Text(value.toString())
          .fontSize(15)
          .fontColor('#E94560')
      }

      Slider({
        value: value,
        min: min,
        max: max,
        step: step,
        style: SliderStyle.OutSet
      })
        .onChange(onChange)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  buildInputField(label: string, value: string, onChange: (value: string) => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor('#CCCCCC')
        .layoutWeight(1)

      TextInput({ text: value, placeholder: 'Enter value...' })
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(6)
        .padding(8)
        .width('60%')
        .onChange(onChange)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }
}
