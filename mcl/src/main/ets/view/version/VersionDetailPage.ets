/**
 * 版本详情页面
 * 移植自: FCL/ui/version/ + FCL/ui/manage/item/
 *
 * 功能: 查看版本信息、管理模组加载器、编辑版本配置
 */
import { GameVersion, LaunchConfig, ModLoaderType } from '../../core/game/GameTypes';
import { VersionManager } from '../../core/game/VersionManager';
import { BMCLAPIDownloadProvider } from '../../core/download/DownloadProvider';
import { FabricInstaller, ForgeInstaller } from '../../core/game/ModLoaderInstaller';
import { ResourceManager, ManagedItemType } from '../../core/game/ModManager';
import { FileUtils } from '../../core/util/FileUtils';
import { GameLauncherService } from '../../service/GameLauncherService';
import { SettingsManager } from '../../core/SettingsManager';
import { promptAction } from '@kit.ArkUI';

@ComponentV2
export struct VersionDetailPage {
  @Param versionId: string = '';
  @Event onClose?: () => void;

  @Local versionInfo: Record<string, Object> | null = null;
  @Local isLoading: boolean = true;
  @Local showLaunchDialog: boolean = false;
  @Local modCount: number = 0;
  @Local saveCount: number = 0;
  @Local resourcePackCount: number = 0;
  @Local totalSize: string = '';
  @Local showLoaderInstall: boolean = false;

  private versionManager: VersionManager = new VersionManager(new BMCLAPIDownloadProvider());
  private settings: SettingsManager = SettingsManager.getInstance();

  aboutToAppear(): void {
    this.loadVersionInfo();
    this.loadStats();
  }

  async loadVersionInfo(): Promise<void> {
    this.isLoading = true;
    try {
      const detail = await this.versionManager.getVersionDetail(this.versionId);
      if (detail) {
        this.versionInfo = {
          id: detail.id,
          type: detail.type,
          mainClass: detail.mainClass,
          javaVersion: detail.javaVersion?.majorVersion ?? 8,
          releaseTime: detail.releaseTime,
          assetIndex: detail.assetIndex?.id ?? 'N/A',
          libraryCount: detail.libraries?.length ?? 0
        } as Record<string, Object>;
      }
    } finally {
      this.isLoading = false;
    }
  }

  loadStats(): void {
    const mcDir = FileUtils.getMinecraftDir();
    this.modCount = ResourceManager.getItemCount(ManagedItemType.MOD);
    this.saveCount = ResourceManager.getItemCount(ManagedItemType.SAVE);
    this.resourcePackCount = ResourceManager.getItemCount(ManagedItemType.RESOURCE_PACK);
    this.totalSize = FileUtils.formatSize(ResourceManager.getTotalSize(ManagedItemType.MOD));
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // 版本头部
          this.buildVersionHeader();

          // 操作按钮
          this.buildActionButtons();

          // 版本信息
          this.buildInfoSection();

          // 模组加载器
          this.buildModLoaderSection();

          // 资源统计
          this.buildStatsSection();

          // 启动配置
          this.buildLaunchConfigSection();
        }
        .width('100%').padding(16)
      }
      .width('100%').height('100%')
      .backgroundColor('#1A1A2E')
    }
    .title(`Version: ${this.versionId}`)
  }

  @Builder
  buildVersionHeader() {
    Row() {
      Column() {
        Text(this.versionId)
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')

        if (this.versionInfo) {
          Text(`Type: ${this.versionInfo['type']} · Java ${this.versionInfo['javaVersion']}`)
            .fontSize(14).fontColor('#999999').margin({ top: 4 })

          Text(`Main: ${this.versionInfo['mainClass'] ?? 'net.minecraft.client.main.Main'}`)
            .fontSize(12).fontColor('#666666').margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(16).backgroundColor('#16213E').borderRadius(12)
    .margin({ bottom: 16 })
  }

  @Builder
  buildActionButtons() {
    Row() {
      // 启动按钮
      Button('Launch Game')
        .fontSize(16).fontColor('#FFFFFF').backgroundColor('#4CAF50')
        .borderRadius(10).padding({ left: 24, right: 24, top: 12, bottom: 12 })
        .layoutWeight(1)
        .onClick(() => this.launchGame())

      // 更多操作
      Button('...')
        .fontSize(16).fontColor('#FFFFFF').backgroundColor('#0F3460')
        .borderRadius(10).padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .margin({ left: 8 })
        .onClick(() => { this.showLoaderInstall = !this.showLoaderInstall; })
    }
    .width('100%').margin({ bottom: 16 })
  }

  @Builder
  buildInfoSection() {
    Column() {
      Text('Version Information')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width('100%').margin({ bottom: 8 })

      if (this.isLoading) {
        LoadingProgress().width(24).height(24).color('#E94560')
      } else if (this.versionInfo) {
        this.buildInfoRow('Release', this.versionInfo['releaseTime'] as string ?? 'Unknown');
        this.buildInfoRow('Main Class', this.versionInfo['mainClass'] as string ?? 'N/A');
        this.buildInfoRow('Java Version', `Java ${this.versionInfo['javaVersion']}`);
        this.buildInfoRow('Asset Index', this.versionInfo['assetIndex'] as string ?? 'N/A');
        this.buildInfoRow('Libraries', `${this.versionInfo['libraryCount'] ?? 0}`);
      }
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  @Builder
  buildModLoaderSection() {
    Column() {
      Text('Mod Loaders')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width('100%').margin({ bottom: 8 })

      if (this.showLoaderInstall) {
        Row() {
          this.buildLoaderBtn('Fabric', ModLoaderType.FABRIC)
          this.buildLoaderBtn('Forge', ModLoaderType.FORGE)
          this.buildLoaderBtn('NeoForge', ModLoaderType.NEOFORGE)
        }
        .width('100%')
      }

      Text('Tap "..." to install mod loaders')
        .fontSize(12).fontColor('#666666').margin({ top: 8 })
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  @Builder
  buildLoaderBtn(label: string, loader: ModLoaderType) {
    Button(label)
      .fontSize(13).fontColor('#FFFFFF').backgroundColor('#0F3460')
      .borderRadius(8).padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .margin({ right: 8 })
      .onClick(() => this.installModLoader(loader))
  }

  @Builder
  buildStatsSection() {
    Column() {
      Text('Resources')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width('100%').margin({ bottom: 8 })

      Row() {
        this.buildStatCard('Mods', this.modCount.toString(), '#2196F3')
        this.buildStatCard('Saves', this.saveCount.toString(), '#4CAF50')
        this.buildStatCard('Resource Packs', this.resourcePackCount.toString(), '#FF9800')
        this.buildStatCard('Total Size', this.totalSize, '#9C27B0')
      }
      .width('100%')
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  @Builder
  buildLaunchConfigSection() {
    Column() {
      Text('Launch Configuration')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width('100%').margin({ bottom: 8 })

      this.buildConfigRow('Memory', `${this.settings.get('minMemory')}MB - ${this.settings.get('maxMemory')}MB`)
      this.buildConfigRow('Java Path', this.settings.get('javaPath') || 'Auto-detect')
      this.buildConfigRow('Game Dir', this.settings.get('gameDir') || FileUtils.getMinecraftDir())
      this.buildConfigRow('Window', `${this.settings.get('windowWidth')}×${this.settings.get('windowHeight')}`)

      Button('Edit in Settings')
        .fontSize(13).fontColor('#E94560').backgroundColor('transparent')
        .border({ width: 1, color: '#E94560' }).borderRadius(8)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .margin({ top: 8 })
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 32 })
  }

  // ========== 子组件 ==========

  @Builder
  buildInfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#999999').width(100)
      Text(value).fontSize(13).fontColor('#FFFFFF').layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  buildStatCard(label: string, value: string, color: string) {
    Column() {
      Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(11).fontColor('#999999').margin({ top: 2 })
    }
    .layoutWeight(1).padding(8)
    .backgroundColor('#0D1B2A').borderRadius(8)
    .margin({ right: 4 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildConfigRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#999999').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#FFFFFF')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }

  // ========== 操作 ==========

  launchGame(): void {
    const gameDir = FileUtils.getMinecraftDir();
    const config: LaunchConfig = {
      version: this.versionId,
      gameDir,
      javaPath: this.settings.get('javaPath') || 'java',
      minMemory: this.settings.get('minMemory'),
      maxMemory: this.settings.get('maxMemory'),
      extraJVMArgs: this.settings.get('extraJVMArgs').split(' ').filter(a => a),
      windowWidth: this.settings.get('windowWidth'),
      windowHeight: this.settings.get('windowHeight'),
      fullscreen: this.settings.get('fullscreen'),
      authUsername: 'Player',
      authUUID: '00000000-0000-0000-0000-000000000000',
      authAccessToken: 'offline',
      demo: false
    };

    GameLauncherService.getInstance().launchGame(config).then(result => {
      if (result.success) {
        promptAction.showToast({ message: 'Game started!' });
      } else {
        promptAction.showToast({ message: `Failed: ${result.error}` });
      }
    });
  }

  async installModLoader(loader: ModLoaderType): Promise<void> {
    promptAction.showToast({ message: `Installing ${loader}...` });

    try {
      if (loader === ModLoaderType.FABRIC) {
        const versions = await FabricInstaller.getLoaderVersions();
        if (versions.length > 0) {
          const result = await FabricInstaller.install(this.versionId, versions[0].version);
          promptAction.showToast({
            message: result.success ? `Fabric ${versions[0].version} installed` : `Failed: ${result.error}`
          });
        }
      } else if (loader === ModLoaderType.FORGE) {
        const recommended = await ForgeInstaller.getRecommended(this.versionId);
        if (recommended) {
          const result = await ForgeInstaller.install(this.versionId, recommended);
          promptAction.showToast({
            message: result.success ? `Forge ${recommended} installed` : `Failed: ${result.error}`
          });
        }
      }
    } catch (err) {
      promptAction.showToast({ message: `Error: ${err}` });
    }
  }
}
