/**
 * FCL 主启动页面
 * 移植自: FCL/ui/main/
 * 显示版本列表、快速启动、最近游玩
 */
import { display } from '@kit.ArkUI';
import { VersionManager } from '../../core/game/VersionManager';
import { BMCLAPIDownloadProvider, RemoteVersion, VersionType } from '../../core/download/DownloadProvider';
import { GameLauncherService } from '../../service/GameLauncherService';
import { SettingsManager, LauncherSettings } from '../../core/SettingsManager';
import { FileUtils } from '../../core/util/FileUtils';
import { LaunchConfig } from '../../core/game/GameTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-MainPage';

@ComponentV2
export struct MainPage {
  @Local installedVersions: string[] = [];
  @Local remoteVersions: RemoteVersion[] = [];
  @Local selectedVersion: string = '';
  @Local isLoading: boolean = false;
  @Local statusMessage: string = '';
  @Local showLaunchDialog: boolean = false;
  @Local launchProgress: string = '';
  @Local recentVersions: string[] = [];

  private versionManager: VersionManager = new VersionManager(new BMCLAPIDownloadProvider());
  private launcher: GameLauncherService = GameLauncherService.getInstance();
  private settings: SettingsManager = SettingsManager.getInstance();

  aboutToAppear(): void {
    this.loadVersions();
  }

  async loadVersions(): Promise<void> {
    this.isLoading = true;
    this.statusMessage = 'Loading versions...';

    try {
      // 加载已安装版本
      this.installedVersions = this.versionManager.getInstalledVersions()
        .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));

      // 尝试加载远程版本列表
      this.remoteVersions = await this.versionManager.getRemoteVersions();

      this.statusMessage = '';
    } catch (err) {
      this.statusMessage = 'Failed to load versions';
      hilog.error(0x0000, TAG, `Load failed: ${err}`);
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  build() {
    Column() {
      // 顶部标题栏
      this.buildHeader();

      // 主体内容
      if (this.isLoading) {
        this.buildLoadingState();
      } else {
        this.buildContent();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
  }

  @Builder
  buildHeader() {
    Row() {
      Text('FCL Launcher')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')

      Blank()

      // 刷新按钮
      Button('Refresh')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#E94560')
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .onClick(() => this.loadVersions())
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213E')
  }

  @Builder
  buildLoadingState() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#E94560')

      Text(this.statusMessage)
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildContent() {
    Scroll() {
      Column() {
        // 快速启动区
        if (this.installedVersions.length > 0) {
          this.buildQuickLaunch();
        }

        // 已安装版本列表
        this.buildInstalledVersions();

        // 可用版本列表
        if (this.remoteVersions.length > 0) {
          this.buildAvailableVersions();
        }

        // 空状态
        if (this.installedVersions.length === 0 && this.remoteVersions.length === 0) {
          this.buildEmptyState();
        }
      }
      .width('100%')
      .padding(16)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  buildQuickLaunch() {
    Column() {
      Text('Quick Launch')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        ForEach(this.installedVersions.slice(0, 5), (version: string) => {
          Button(version)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#0F3460')
            .borderRadius(12)
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .margin({ right: 8 })
            .onClick(() => this.launchVersion(version))
        })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  @Builder
  buildInstalledVersions() {
    Column() {
      Row() {
        Text(`Installed Versions (${this.installedVersions.length})`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .margin({ bottom: 12 })

      ForEach(this.installedVersions, (version: string) => {
        this.buildVersionCard(version, true);
      })
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  @Builder
  buildAvailableVersions() {
    Column() {
      Text('Available Versions')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ bottom: 12 })

      ForEach(
        this.remoteVersions.filter(v => !this.installedVersions.includes(v.version)).slice(0, 20),
        (version: RemoteVersion) => {
          this.buildRemoteVersionCard(version);
        }
      )
    }
    .width('100%')
  }

  @Builder
  buildVersionCard(version: string, isInstalled: boolean) {
    Row() {
      Column() {
        Text(version)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')

        Text(isInstalled ? 'Installed' : 'Available')
          .fontSize(12)
          .fontColor(isInstalled ? '#4CAF50' : '#FF9800')
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (isInstalled) {
        // 启动按钮
        Button('Launch')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#E94560')
          .borderRadius(8)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => this.launchVersion(version))

        // 删除按钮
        Button('Delete')
          .fontSize(12)
          .fontColor('#FF5252')
          .backgroundColor('transparent')
          .border({ width: 1, color: '#FF5252' })
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .margin({ left: 8 })
          .onClick(() => this.deleteVersion(version))
      } else {
        Button('Install')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#0F3460')
          .borderRadius(8)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => this.installVersion(version))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213E')
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  @Builder
  buildRemoteVersionCard(version: RemoteVersion) {
    Row() {
      Column() {
        Text(version.version)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')

        Text(`${version.type} · ${version.releaseTime}`)
          .fontSize(12)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Button('Install')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .onClick(() => this.installVersion(version.version))
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213E')
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text('No versions found')
        .fontSize(18)
        .fontColor('#999999')
        .margin({ top: 64, bottom: 8 })

      Text('Check your network connection and refresh')
        .fontSize(14)
        .fontColor('#666666')
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ========== 操作方法 ==========

  async launchVersion(version: string): Promise<void> {
    this.launchProgress = `Launching ${version}...`;
    this.showLaunchDialog = true;

    const gameDir = FileUtils.getMinecraftDir();
    const javaPath = this.settings.get('javaPath') || 'java';
    const minMemory = this.settings.get('minMemory');
    const maxMemory = this.settings.get('maxMemory');
    const extraJVMArgs = this.settings.get('extraJVMArgs').split(' ').filter(a => a.length > 0);

    const config: LaunchConfig = {
      version,
      gameDir,
      javaPath,
      minMemory,
      maxMemory,
      extraJVMArgs,
      windowWidth: this.settings.get('windowWidth'),
      windowHeight: this.settings.get('windowHeight'),
      fullscreen: this.settings.get('fullscreen'),
      authUsername: 'Player',
      authUUID: '00000000-0000-0000-0000-000000000000',
      authAccessToken: 'offline',
      demo: false
    };

    const result = await this.launcher.launchGame(config);

    if (result.success) {
      this.launchProgress = `Game started! PID: ${result.pid}`;
    } else {
      this.launchProgress = `Failed: ${result.error}`;
    }

    setTimeout(() => {
      this.showLaunchDialog = false;
    }, 3000);
  }

  async installVersion(version: string): Promise<void> {
    this.statusMessage = `Installing ${version}...`;
    this.isLoading = true;

    try {
      await this.versionManager.installVersion(version, {
        onProgress: (progress) => {
          this.statusMessage =
            `${progress.stage}: ${progress.completedFiles}/${progress.totalFiles} files`;
        },
        onComplete: () => {
          this.statusMessage = `${version} installed successfully!`;
          this.loadVersions();
        },
        onError: (error) => {
          this.statusMessage = `Install failed: ${error}`;
          this.isLoading = false;
        }
      });
    } catch (err) {
      this.statusMessage = `Install failed: ${err}`;
    } finally {
      this.isLoading = false;
    }
  }

  deleteVersion(version: string): void {
    if (this.versionManager.deleteVersion(version)) {
      this.loadVersions();
    }
  }
}
