/**
 * 世界存档管理页面
 * 移植自: FCL/ui/manage/WorldListPage + WorldInfoPage + WorldExportDialog
 */
import { ResourceManager, ManagedItemType, SaveInfo } from '../../core/game/ModManager';
import { FileUtils } from '../../core/util/FileUtils';
import { promptAction } from '@kit.ArkUI';

@ComponentV2
export struct WorldManagePage {
  @Local saves: SaveInfo[] = [];
  @Local isLoading: boolean = false;
  @Local searchQuery: string = '';
  @Local selectedSave: SaveInfo | null = null;
  @Local showDeleteConfirm: boolean = false;
  @Local showExportDialog: boolean = false;
  @Local exportPath: string = '';

  aboutToAppear(): void {
    this.loadSaves();
  }

  loadSaves(): void {
    this.isLoading = true;
    const items = ResourceManager.listItems(ManagedItemType.SAVE);

    this.saves = items.map(item => {
      const info: SaveInfo = {
        name: item.name,
        path: item.path,
        size: item.size,
        lastModified: item.lastModified,
        isDirectory: true,
        enabled: true,
        type: ManagedItemType.SAVE,
        metadata: item.metadata
      };

      // 读取 level.dat 信息
      const saveInfo = ResourceManager.getSaveInfo(item.path);
      if (saveInfo.levelName) {
        info.levelName = saveInfo.levelName;
      }
      if (saveInfo.gameVersion) {
        info.gameVersion = saveInfo.gameVersion;
      }
      if (saveInfo.iconPath) {
        info.iconPath = saveInfo.iconPath;
      }

      return info;
    });

    this.applyFilter();
    this.isLoading = false;
  }

  applyFilter(): void {
    if (this.searchQuery.trim()) {
      const q = this.searchQuery.toLowerCase();
      this.saves = this.saves.filter(s =>
        s.name.toLowerCase().includes(q) ||
        (s.levelName?.toLowerCase().includes(q) ?? false)
      );
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('World Saves')
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Blank()
          Text(`${this.saves.length} worlds`).fontSize(12).fontColor('#999999')
        }
        .width('100%').padding(16)

        if (this.saves.length === 0) {
          this.buildEmptyState();
        } else {
          List() {
            ForEach(this.saves, (save: SaveInfo) => {
              ListItem() {
                this.buildSaveCard(save);
              }
            })
          }
          .layoutWeight(1).scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
        }
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')

      if (this.showDeleteConfirm && this.selectedSave) {
        this.buildDeleteDialog();
      }
    }
  }

  @Builder
  buildSaveCard(save: SaveInfo) {
    Row() {
      // 存档图标
      Stack() {
        if (save.iconPath && FileUtils.exists(save.iconPath)) {
          Image(save.iconPath).width(48).height(48).borderRadius(8)
        } else {
          Column() {
            Text('🌍').fontSize(28)
          }
          .width(48).height(48).borderRadius(8).backgroundColor('#0F3460')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        }
      }
      .margin({ right: 12 })

      Column() {
        Text(save.levelName ?? save.name)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(save.gameVersion ?? 'Unknown version')
            .fontSize(12).fontColor('#999999')
          if (save.gameMode) {
            Text(` · ${save.gameMode}`).fontSize(12).fontColor('#666666')
          }
        }
        .margin({ top: 2 })

        Text(FileUtils.formatSize(save.size ?? 0))
          .fontSize(11).fontColor('#555555').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      Column() {
        Button('Info').fontSize(11).fontColor('#999999').backgroundColor('#0F3460')
          .borderRadius(4).padding({ left: 8, right: 8, top: 4, bottom: 4 }).margin({ bottom: 4 })
          .onClick(() => { this.selectedSave = save; })

        Button('Export').fontSize(11).fontColor('#2196F3').backgroundColor('rgba(33,150,243,0.1)')
          .borderRadius(4).padding({ left: 8, right: 8, top: 4, bottom: 4 }).margin({ bottom: 4 })
          .onClick(() => this.exportSave(save))

        Button('Delete').fontSize(11).fontColor('#FF5252').backgroundColor('rgba(255,82,82,0.1)')
          .borderRadius(4).padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.selectedSave = save;
            this.showDeleteConfirm = true;
          })
      }
      .margin({ left: 8 })
    }
    .width('100%').padding(14).backgroundColor('#16213E').borderRadius(10)
    .margin({ top: 6, left: 16, right: 16 })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text('No world saves found')
        .fontSize(18).fontColor('#999999').margin({ top: 64, bottom: 8 })
      Text('Create a new world in Minecraft to see it here')
        .fontSize(14).fontColor('#666666')
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildDeleteDialog() {
    Column() {
      Column() {
        Text('Delete World')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').margin({ bottom: 12 })
        Text(`Delete "${this.selectedSave?.name ?? ''}"?`)
          .fontSize(14).fontColor('#CCCCCC').margin({ bottom: 6 })
        Text('This will permanently delete all save data!')
          .fontSize(12).fontColor('#FF5252').margin({ bottom: 20 })
        Row() {
          Button('Cancel').fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => { this.showDeleteConfirm = false; })
          Button('Delete Forever')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#FF5252')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .margin({ left: 16 })
            .onClick(() => {
              if (this.selectedSave) {
                ResourceManager.deleteItem(this.selectedSave);
                this.showDeleteConfirm = false;
                this.loadSaves();
              }
            })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('80%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showDeleteConfirm = false; })
  }

  exportSave(save: SaveInfo): void {
    // 导出为 ZIP 文件
    const exportDir = `${FileUtils.getMinecraftDir()}/exports`;
    FileUtils.mkdirs(exportDir);
    const exportPath = `${exportDir}/${save.name}_${Date.now()}.zip`;

    // TODO: ZIP 压缩使用 @ohos.zlib
    this.exportPath = exportPath;
    this.showExportDialog = true;

    promptAction.showToast({ message: `Exporting to ${exportPath}` });
  }
}
