import { httpGet, httpPost } from '../../core/util/HttpUtils';
/**
 * 下载中心完整页面
 * 移植自: FCL/ui/download/
 * 功能: 版本浏览、搜索、筛选、模组加载器选择、一键安装
 */
import { VersionManager, InstallProgress } from '../../core/game/VersionManager';
import { BMCLAPIDownloadProvider, RemoteVersion, VersionType } from '../../core/download/DownloadProvider';
import { ModLoaderType } from '../../core/game/GameTypes';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-DownloadPage';

/** 模组加载器版本条目 */
interface ModLoaderVersion {
  version: string;
  stable: boolean;
}

@ComponentV2
export struct DownloadPage {
  @Local versions: RemoteVersion[] = [];
  @Local filteredVersions: RemoteVersion[] = [];
  @Local isLoading: boolean = false;
  @Local statusMessage: string = '';
  @Local searchQuery: string = '';
  @Local filterType: string = 'all'; // all, release, snapshot
  @Local showInstallProgress: boolean = false;
  @Local installProgress: InstallProgress = {
    stage: 'preparing', totalFiles: 0, completedFiles: 0,
    currentFile: '', totalSize: 0, downloadedSize: 0
  };
  @Local selectedVersion: string = '';
  @Local showVersionDetail: boolean = false;
  @Local versionDetail: Record<string, Object> | null = null;

  // Fabric 版本列表
  @Local fabricVersions: ModLoaderVersion[] = [];
  @Local selectedFabricVersion: string = '';

  private versionManager: VersionManager = new VersionManager(new BMCLAPIDownloadProvider());

  aboutToAppear(): void {
    this.loadVersions();
    this.loadFabricVersions();
  }

  async loadVersions(): Promise<void> {
    this.isLoading = true;
    this.statusMessage = 'Loading available versions...';
    try {
      this.versions = await this.versionManager.getRemoteVersions();
      this.applyFilters();
      this.statusMessage = '';
    } catch (err) {
      this.statusMessage = 'Failed to load versions';
    } finally {
      this.isLoading = false;
    }
  }

  async loadFabricVersions(): Promise<void> {
    try {
      const response = await httpGet('https://meta.fabricmc.net/v2/versions/loader');
      const data = await response.json() as Array<Record<string, Object>>;
      this.fabricVersions = data.slice(0, 20);
    } catch {
      // Fabric 元数据加载失败, 不影响主流程
    }
  }

  applyFilters(): void {
    let result = [...this.versions];

    // 搜索过滤
    if (this.searchQuery.trim()) {
      const q = this.searchQuery.toLowerCase();
      result = result.filter(v => v.version.toLowerCase().includes(q));
    }

    // 类型过滤
    if (this.filterType !== 'all') {
      result = result.filter(v => v.type === this.filterType);
    }

    this.filteredVersions = result;
  }

  build() {
    Stack() {
      Column() {
        // 搜索和过滤
        this.buildSearchBar();

        // 列表
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color('#E94560')
            Text(this.statusMessage).fontSize(14).fontColor('#999999').margin({ top: 12 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          this.buildVersionList();
        }
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')

      // 安装进度覆盖层
      if (this.showInstallProgress) {
        this.buildInstallOverlay();
      }

      // 版本详情对话框
      if (this.showVersionDetail) {
        this.buildVersionDetailDialog();
      }
    }
  }

  @Builder
  buildSearchBar() {
    Column() {
      // 搜索框
      TextInput({ placeholder: 'Search versions...', text: this.searchQuery })
        .fontSize(14).fontColor('#FFFFFF')
        .backgroundColor('#16213E').borderRadius(8)
        .padding(12).width('100%')
        .onChange((value: string) => {
          this.searchQuery = value;
          this.applyFilters();
        })

      // 类型过滤标签
      Row() {
        this.buildFilterChip('All', 'all');
        this.buildFilterChip('Release', 'release');
        this.buildFilterChip('Snapshot', 'snapshot');
        this.buildFilterChip('Beta', 'old_beta');
      }
      .width('100%').margin({ top: 8 })

      // 数量统计
      Text(`${this.filteredVersions.length} versions found`)
        .fontSize(12).fontColor('#666666').margin({ top: 4 })
    }
    .width('100%').padding(16).backgroundColor('#0D1B2A')
  }

  @Builder
  buildFilterChip(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.filterType === value ? '#FFFFFF' : '#999999')
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.filterType === value ? '#E94560' : '#0F3460')
    .borderRadius(12)
    .margin({ right: 6 })
    .onClick(() => {
      this.filterType = value;
      this.applyFilters();
    })
  }

  @Builder
  buildVersionList() {
    List() {
      // 按类型分组显示
      if (this.filterType === 'all') {
        // 仅显示最近的快照版本
      }

      ForEach(this.filteredVersions.slice(0, 50), (version: RemoteVersion) => {
        ListItem() {
          this.buildVersionCard(version);
        }
      })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
  }

  @Builder
  buildVersionCard(version: RemoteVersion) {
    Row() {
      Column() {
        Row() {
          Text(version.version)
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')

          // 版本类型标签
          Text(version.type)
            .fontSize(10)
            .fontColor(this.getTypeColor(version.type))
            .backgroundColor(this.getTypeBgColor(version.type))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ left: 8 })
        }

        Text(version.releaseTime)
          .fontSize(12).fontColor('#999999').margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 已安装标记
      if (this.versionManager.isVersionInstalled(version.version)) {
        Text('Installed ✓')
          .fontSize(12).fontColor('#4CAF50')
      } else {
        Button('Install')
          .fontSize(13).fontColor('#FFFFFF')
          .backgroundColor('#E94560').borderRadius(8)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => this.startInstall(version.version))
      }

      // 详情按钮
      Button('Detail')
        .fontSize(12).fontColor('#999999')
        .backgroundColor('transparent')
        .border({ width: 1, color: '#555555' }).borderRadius(6)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => this.showDetail(version))
    }
    .width('100%').padding(16)
    .backgroundColor('#16213E').borderRadius(12).margin({ top: 8, left: 16, right: 16 })
  }

  @Builder
  buildInstallOverlay() {
    Column() {
      Column() {
        Text('Installing')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .margin({ bottom: 16 })

        // 进度条
        Progress({
          value: this.installProgress.totalFiles > 0 ?
            this.installProgress.completedFiles / this.installProgress.totalFiles * 100 : 0,
          total: 100
        })
          .width('100%')
          .color('#E94560')
          .style(ProgressStyle.Capsule)

        Text(`${this.installProgress.completedFiles} / ${this.installProgress.totalFiles} files`)
          .fontSize(14).fontColor('#CCCCCC').margin({ top: 12 })

        Text(this.installProgress.currentFile)
          .fontSize(12).fontColor('#999999').margin({ top: 4 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`Stage: ${this.installProgress.stage}`)
          .fontSize(12).fontColor('#E94560').margin({ top: 8 })

        // 取消按钮
        Button('Cancel')
          .fontSize(14).fontColor('#FF5252').backgroundColor('transparent')
          .border({ width: 1, color: '#FF5252' }).borderRadius(8)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .margin({ top: 20 })
          .onClick(() => { this.showInstallProgress = false; })
      }
      .padding(32).backgroundColor('#16213E').borderRadius(16).width('80%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.8)')
  }

  @Builder
  buildVersionDetailDialog() {
    Column() {
      Column() {
        Text(`Version: ${this.selectedVersion}`)
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .margin({ bottom: 16 })

        // 可选模组加载器
        Text('Install with Mod Loader:')
          .fontSize(14).fontColor('#999999').margin({ bottom: 8 })

        Row() {
          this.buildLoaderOption('Vanilla', ModLoaderType.FABRIC, false)
          this.buildLoaderOption('Fabric', ModLoaderType.FABRIC, true)
        }
        .width('100%').margin({ bottom: 12 })

        Row() {
          this.buildLoaderOption('Forge', ModLoaderType.FORGE, false)
          this.buildLoaderOption('NeoForge', ModLoaderType.NEOFORGE, false)
        }
        .width('100%')

        // Fabric 版本选择
        if (this.selectedFabricVersion) {
          Text(`Fabric: ${this.selectedFabricVersion}`)
            .fontSize(12).fontColor('#4CAF50').margin({ top: 8 })
        }

        // 操作按钮
        Row() {
          Button('Install Vanilla')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => {
              this.showVersionDetail = false;
              this.startInstall(this.selectedVersion);
            })

          Button('Close')
            .fontSize(14).fontColor('#999999').backgroundColor('transparent')
            .border({ width: 1, color: '#555555' }).borderRadius(8)
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .margin({ left: 12 })
            .onClick(() => { this.showVersionDetail = false; })
        }
        .width('100%').justifyContent(FlexAlign.Center).margin({ top: 24 })
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('85%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showVersionDetail = false; })
  }

  @Builder
  buildLoaderOption(label: string, loader: ModLoaderType, isFabric: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(isFabric && this.selectedFabricVersion ? '#4CAF50' : '#CCCCCC')
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.selectedFabricVersion && isFabric ? 'rgba(76,175,80,0.15)' : '#0F3460')
    .borderRadius(8)
    .margin({ right: 8 })
    .onClick(() => {
      if (isFabric) {
        if (this.fabricVersions.length > 0) {
          this.selectedFabricVersion = this.fabricVersions[0].version;
        }
      }
    })
  }

  // ========== 操作 ==========

  showDetail(version: RemoteVersion): void {
    this.selectedVersion = version.version;
    this.showVersionDetail = true;
  }

  async startInstall(versionId: string): Promise<void> {
    this.showInstallProgress = true;
    this.selectedVersion = versionId;

    try {
      await this.versionManager.installVersion(versionId, {
        onProgress: (progress: InstallProgress): void => {
          this.installProgress = progress;
          if (progress.stage === 'error') {
            promptAction.showToast({ message: `Install failed: ${progress.error}` });
          }
        },
        onComplete: (): void => {
          promptAction.showToast({ message: `${versionId} installed successfully!` });
          setTimeout(() => { this.showInstallProgress = false; }, 1500);
        },
        onError: (error: string): void => {
          promptAction.showToast({ message: `Error: ${error}` });
        }
      });
    } catch (err) {
      promptAction.showToast({ message: `Error: ${err}` });
    }
  }

  // ========== 工具方法 ==========

  getTypeColor(type: VersionType): string {
    switch (type) {
      case VersionType.RELEASE: return '#4CAF50';
      case VersionType.SNAPSHOT: return '#FF9800';
      case VersionType.OLD_BETA: return '#2196F3';
      case VersionType.OLD_ALPHA: return '#F44336';
      default: return '#999999';
    }
  }

  getTypeBgColor(type: VersionType): string {
    switch (type) {
      case VersionType.RELEASE: return 'rgba(76,175,80,0.15)';
      case VersionType.SNAPSHOT: return 'rgba(255,152,0,0.15)';
      default: return 'rgba(255,255,255,0.08)';
    }
  }
}
