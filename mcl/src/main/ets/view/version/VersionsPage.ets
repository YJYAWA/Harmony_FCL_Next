/**
 * 版本配置/Profile管理页面
 * 移植自: FCL/ui/version/ (VersionListPage, VersionUI, AddProfileDialog, etc.)
 */
import { VersionManager } from '../../core/game/VersionManager';
import { BMCLAPIDownloadProvider } from '../../core/download/DownloadProvider';
import { LibraryAnalyzer } from '../../core/game/LibraryAnalyzer';
import { GameVersion, ModLoaderType, LaunchConfig } from '../../core/game/GameTypes';
import { FileUtils } from '../../core/util/FileUtils';
import { SettingsManager } from '../../core/SettingsManager';
import { GameLauncherService } from '../../service/GameLauncherService';
import { NavigationService, RouteNames } from '../../common/NavigationRouter';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-VersionsPage';

/** 版本 Profile 条目 */
interface VersionProfile {
  id: string;
  name: string;
  versionId: string;
  gameDir: string;
  javaPath: string;
  lastPlayed: number;
  playCount: number;
  loaderInfo: string;
}

@ComponentV2
export struct VersionsPage {
  @Local profiles: VersionProfile[] = [];
  @Local installedVersions: string[] = [];
  @Local isLoading: boolean = false;
  @Local showAddDialog: boolean = false;
  @Local showDuplicateDialog: boolean = false;
  @Local showRenameDialog: boolean = false;
  @Local selectedVersion: string = '';
  @Local newProfileName: string = '';
  @Local renameTarget: string = '';

  private versionManager: VersionManager = new VersionManager(new BMCLAPIDownloadProvider());
  private settings: SettingsManager = SettingsManager.getInstance();

  aboutToAppear(): void {
    this.loadVersions();
    this.loadProfiles();
  }

  loadVersions(): void {
    this.isLoading = true;
    this.installedVersions = this.versionManager.getInstalledVersions()
      .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
    this.isLoading = false;
  }

  loadProfiles(): void {
    const path = `${FileUtils.getMinecraftDir()}/fcl_profiles.json`;
    this.profiles = FileUtils.readJSON<VersionProfile[]>(path) ?? [];
  }

  saveProfiles(): void {
    const path = `${FileUtils.getMinecraftDir()}/fcl_profiles.json`;
    FileUtils.writeJSON(path, this.profiles);
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('Version & Profiles').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Blank()
          Button('+ Profile').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.showAddDialog = true; })
        }
        .width('100%').padding(16)

        // Profiles 列表
        if (this.profiles.length > 0) {
          Text('Profiles').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E94560')
            .width('100%').padding({ left: 16, top: 8 })
          List() {
            ForEach(this.profiles, (profile: VersionProfile) => {
              ListItem() {
                this.buildProfileCard(profile);
              }
            })
          }
          .height(Math.min(this.profiles.length * 80 + 20, 300))
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
        }

        // 已安装版本
        Text(`Installed Versions (${this.installedVersions.length})`)
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E94560')
          .width('100%').padding({ left: 16, top: 16, bottom: 8 })

        if (this.isLoading) {
          LoadingProgress().width(24).height(24).color('#E94560')
        } else if (this.installedVersions.length === 0) {
          Text('No versions installed').fontSize(14).fontColor('#999999')
            .width('100%').padding(16).textAlign(TextAlign.Center)
        } else {
          List() {
            ForEach(this.installedVersions, (versionId: string) => {
              ListItem() {
                this.buildVersionCard(versionId);
              }
            })
          }
          .layoutWeight(1).scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
        }
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')

      if (this.showAddDialog) {
        this.buildAddProfileDialog();
      }
      if (this.showDuplicateDialog) {
        this.buildDuplicateDialog();
      }
      if (this.showRenameDialog) {
        this.buildRenameDialog();
      }
    }
  }

  @Builder
  buildProfileCard(profile: VersionProfile) {
    Row() {
      Column() {
        Text(profile.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        Text(`MC ${profile.versionId} · ${profile.loaderInfo || 'Vanilla'}`)
          .fontSize(12).fontColor('#999999').margin({ top: 2 })
        Text(`Played ${profile.playCount} times · Last: ${new Date(profile.lastPlayed).toLocaleDateString()}`)
          .fontSize(11).fontColor('#666666').margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Button('Launch').fontSize(12).fontColor('#FFFFFF').backgroundColor('#4CAF50')
        .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .margin({ right: 6 })
        .onClick(() => this.launchProfile(profile))

      Button('Delete').fontSize(12).fontColor('#FF5252').backgroundColor('rgba(255,82,82,0.1)')
        .borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.profiles = this.profiles.filter(p => p.id !== profile.id);
          this.saveProfiles();
        })
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(8)
    .margin({ top: 4, left: 16, right: 16 })
  }

  @Builder
  buildVersionCard(versionId: string) {
    Row() {
      Column() {
        Text(versionId).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        Text('Installed').fontSize(12).fontColor('#4CAF50').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Button('Launch').fontSize(12).fontColor('#FFFFFF').backgroundColor('#4CAF50')
        .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 }).margin({ right: 6 })
        .onClick(() => this.launchVersion(versionId))

      Button('Detail').fontSize(12).fontColor('#999999').backgroundColor('#0F3460')
        .borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 }).margin({ right: 6 })
        .onClick(() => NavigationService.push(RouteNames.VERSION_DETAIL, { versionId } as ESObject))

      Button('More').fontSize(12).fontColor('#999999').backgroundColor('rgba(255,255,255,0.05)')
        .borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => { this.selectedVersion = versionId; })
    }
    .width('100%').padding(12).backgroundColor('#16213E').borderRadius(8)
    .margin({ top: 4, left: 16, right: 16 })
  }

  @Builder
  buildAddProfileDialog() {
    Column() {
      Column() {
        Text('Create Profile').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').margin({ bottom: 12 })
        Text('Profile Name').fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        TextInput({ placeholder: 'My Profile', text: this.newProfileName }).fontSize(14).fontColor('#FFFFFF')
          .backgroundColor('#0F3460').borderRadius(8).padding(12).width('100%').margin({ bottom: 16 })
          .onChange((v: string) => { this.newProfileName = v; })

        Text('Select Version').fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        Row() {
          ForEach(this.installedVersions.slice(0, 6), (v: string) => {
            Button(v).fontSize(12)
              .fontColor(this.selectedVersion === v ? '#FFFFFF' : '#999999')
              .backgroundColor(this.selectedVersion === v ? '#E94560' : '#0F3460')
              .borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ right: 4 })
              .onClick(() => { this.selectedVersion = v; })
          })
        }
        .width('100%').margin({ bottom: 16 })

        Row() {
          Button('Cancel').fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => { this.showAddDialog = false; })
          Button('Create').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 }).margin({ left: 16 })
            .onClick(() => {
              if (this.newProfileName && this.selectedVersion) {
                this.profiles.push({
                  id: `profile_${Date.now()}`,
                  name: this.newProfileName,
                  versionId: this.selectedVersion,
                  gameDir: FileUtils.getMinecraftDir(),
                  javaPath: '',
                  lastPlayed: 0, playCount: 0, loaderInfo: 'Vanilla'
                });
                this.saveProfiles();
                this.showAddDialog = false;
              }
            })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('85%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showAddDialog = false; })
  }

  @Builder
  buildDuplicateDialog() {
    Column() {
      Column() {
        Text('Duplicate Version').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').margin({ bottom: 12 })
        Text(`Create a copy of "${this.selectedVersion}"?`)
          .fontSize(14).fontColor('#CCCCCC').margin({ bottom: 16 })
        Row() {
          Button('Cancel').fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => { this.showDuplicateDialog = false; })
          Button('Duplicate').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 }).margin({ left: 16 })
            .onClick(() => {
              const src = `${FileUtils.getVersionsDir()}/${this.selectedVersion}`;
              const dst = `${FileUtils.getVersionsDir()}/${this.selectedVersion}_copy`;
              FileUtils.copy(src + '/' + this.selectedVersion + '.json', dst + '/' + this.selectedVersion + '_copy' + '.json');
              this.showDuplicateDialog = false;
              this.loadVersions();
            })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('80%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showDuplicateDialog = false; })
  }

  @Builder
  buildRenameDialog() {
    Column() {
      Column() {
        Text('Rename Version').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').margin({ bottom: 12 })
        TextInput({ placeholder: 'New name', text: this.renameTarget }).fontSize(14).fontColor('#FFFFFF')
          .backgroundColor('#0F3460').borderRadius(8).padding(12).width('100%').margin({ bottom: 16 })
          .onChange((v: string) => { this.renameTarget = v; })
        Row() {
          Button('Cancel').fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => { this.showRenameDialog = false; })
          Button('Rename').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 }).margin({ left: 16 })
            .onClick(() => { this.showRenameDialog = false; })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('80%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showRenameDialog = false; })
  }

  launchVersion(versionId: string): void {
    const config: LaunchConfig = {
      version: versionId, gameDir: FileUtils.getMinecraftDir(),
      javaPath: this.settings.get('javaPath') || 'java',
      minMemory: this.settings.get('minMemory'), maxMemory: this.settings.get('maxMemory'),
      extraJVMArgs: this.settings.get('extraJVMArgs').split(' ').filter(a => a),
      windowWidth: this.settings.get('windowWidth'), windowHeight: this.settings.get('windowHeight'),
      fullscreen: this.settings.get('fullscreen'),
      authUsername: 'Player', authUUID: '00000000-0000-0000-0000-000000000000',
      authAccessToken: 'offline', demo: false
    };
    GameLauncherService.getInstance().launchGame(config).then(r => {
      promptAction.showToast({ message: r.success ? 'Game started!' : `Failed: ${r.error}` });
    });
  }

  launchProfile(profile: VersionProfile): void {
    profile.lastPlayed = Date.now();
    profile.playCount++;
    this.saveProfiles();
    this.launchVersion(profile.versionId);
  }
}
