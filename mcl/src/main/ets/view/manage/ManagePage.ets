/**
 * 模组/资源/存档管理页面
 * 移植自: FCL/ui/manage/
 */
import { ResourceManager, ManagedItemType, ManagedItem }
  from '../../core/game/ModManager';
import { FileUtils } from '../../core/util/FileUtils';
import { GameArchiveIO } from '../../core/archive/GameArchiveIO';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/** 各资源类型的允许扩展名（与 picker 的 fileSuffixFilters 对应） */
const MOD_EXTENSIONS: string[] = ['.jar'];
const ZIP_EXTENSIONS: string[] = ['.zip'];

/** 管理页顶部标签 */
interface ManagedTab {
  type: ManagedItemType;
  label: string;
}

@ComponentV2
export struct ManagePage {
  @Local items: ManagedItem[] = [];
  @Local selectedType: ManagedItemType = ManagedItemType.MOD;
  @Local isLoading: boolean = false;
  @Local searchQuery: string = '';
  @Local showDeleteConfirm: boolean = false;
  @Local deleteTarget: ManagedItem | null = null;

  private readonly tabs: ManagedTab[] = [
    { type: ManagedItemType.MOD, label: 'Mods' },
    { type: ManagedItemType.RESOURCE_PACK, label: 'Resource Packs' },
    { type: ManagedItemType.SHADER_PACK, label: 'Shaders' },
    { type: ManagedItemType.SAVE, label: 'Saves' },
    { type: ManagedItemType.DATA_PACK, label: 'Data Packs' }
  ];

  aboutToAppear(): void {
    this.loadItems();
  }

  loadItems(): void {
    this.isLoading = true;
    this.items = ResourceManager.listItems(this.selectedType);

    if (this.searchQuery.trim()) {
      const q = this.searchQuery.toLowerCase();
      this.items = this.items.filter(i => i.name.toLowerCase().includes(q));
    }

    this.isLoading = false;
  }

  build() {
    Stack() {
      Column() {
        // 顶部切换栏
        this.buildTypeTabs();

        // 搜索和操作
        this.buildToolbar();

        // 统计
        Row() {
          Text(`${this.items.length} items`)
            .fontSize(12).fontColor('#999999')
            .layoutWeight(1)

          Text(`Total: ${FileUtils.formatSize(ResourceManager.getTotalSize(this.selectedType))}`)
            .fontSize(12).fontColor('#666666')
        }
        .width('100%').padding({ left: 16, right: 16, top: 8 })

        // 列表
        if (this.items.length === 0) {
          this.buildEmptyState();
        } else {
          List() {
            ForEach(this.items, (item: ManagedItem) => {
              ListItem() {
                this.buildItemCard(item);
              }
            })
          }
          .layoutWeight(1).scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
        }
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')

      // 删除确认
      if (this.showDeleteConfirm && this.deleteTarget) {
        this.buildDeleteDialog();
      }
    }
  }

  @Builder
  buildTypeTabs() {
    Scroll() {
      Row() {
        ForEach(
          this.tabs,
          (tab: ManagedTab) => {
            Text(tab.label)
              .fontSize(13)
              .fontColor(this.selectedType === tab.type ? '#FFFFFF' : '#999999')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(this.selectedType === tab.type ? '#E94560' : '#16213E')
              .borderRadius(16)
              .margin({ right: 6 })
              .onClick(() => {
                this.selectedType = tab.type;
                this.loadItems();
              })
          }
        )
      }
      .width('auto')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .backgroundColor('#0D1B2A')
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  @Builder
  buildToolbar() {
    Row() {
      TextInput({ placeholder: 'Search...', text: this.searchQuery })
        .fontSize(14).fontColor('#FFFFFF')
        .backgroundColor('#0F3460').borderRadius(8)
        .padding(10).layoutWeight(1)
        .onChange((value: string) => {
          this.searchQuery = value;
          this.loadItems();
        })

      Button('Import')
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#0F3460')
        .borderRadius(8).padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .margin({ left: 8 })
        .onClick(() => {
          this.importResources();
        })
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  buildItemCard(item: ManagedItem) {
    Row() {
      // 禁用指示器
      if (!item.enabled) {
        Text('✕')
          .fontSize(16).fontColor('#FF5252').margin({ right: 12 })
      }

      Column() {
        Text(item.name)
          .fontSize(15)
          .fontColor(item.enabled ? '#FFFFFF' : '#666666')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(item.isDirectory ? 'Directory' : 'File')
            .fontSize(11).fontColor('#666666')
          Text(' · ')
            .fontSize(11).fontColor('#555555')
          Text(FileUtils.formatSize(item.size))
            .fontSize(11).fontColor('#666666')
        }
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      // 操作按钮
      Button(item.enabled ? 'Disable' : 'Enable')
        .fontSize(11)
        .fontColor(item.enabled ? '#FF9800' : '#4CAF50')
        .backgroundColor(item.enabled ? 'rgba(255,152,0,0.15)' : 'rgba(76,175,80,0.15)')
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ right: 6 })
        .onClick(() => {
          if (ResourceManager.toggleItem(item)) {
            this.loadItems();
          }
        })

      Button('Delete')
        .fontSize(11).fontColor('#FF5252')
        .backgroundColor('rgba(255,82,82,0.1)').borderRadius(6)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.deleteTarget = item;
          this.showDeleteConfirm = true;
        })
    }
    .width('100%').padding(14)
    .backgroundColor('#16213E').borderRadius(10)
    .margin({ top: 6, left: 16, right: 16 })
  }

  /**
   * 从系统文件选择器导入资源到当前分类目录。
   * 鸿蒙权限：走 DocumentViewPicker，用户显式授权，无需额外 user_grant 权限。
   */
  private async importResources(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const targetDir = ResourceManager.getDirectory(this.selectedType);
    const exts = this.selectedType === ManagedItemType.MOD ? MOD_EXTENSIONS : ZIP_EXTENSIONS;
    try {
      const result = await GameArchiveIO.importResourceFiles(ctx, targetDir, exts);
      if (result.cancelled) {
        return;
      }
      promptAction.showToast({ message: result.message });
      this.loadItems();
    } catch (err) {
      promptAction.showToast({ message: `导入失败: ${err}` });
    }
  }

  @Builder
  buildEmptyState() {    Column() {
      Text('No items found')
        .fontSize(18).fontColor('#999999').margin({ top: 64, bottom: 8 })
      Text('Import files or download from the store')
        .fontSize(14).fontColor('#666666')
      Button('Refresh')
        .fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
        .borderRadius(8).padding({ left: 24, right: 24, top: 10, bottom: 10 })
        .margin({ top: 16 })
        .onClick(() => this.loadItems())
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildDeleteDialog() {
    Column() {
      Column() {
        Text('Confirm Delete')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .margin({ bottom: 12 })

        Text(`Delete "${this.deleteTarget?.name ?? ''}"?`)
          .fontSize(14).fontColor('#CCCCCC').margin({ bottom: 8 })

        Text('This action cannot be undone')
          .fontSize(12).fontColor('#FF5252').margin({ bottom: 20 })

        Row() {
          Button('Cancel')
            .fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .onClick(() => { this.showDeleteConfirm = false; })

          Button('Delete')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#FF5252')
            .borderRadius(8).padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .margin({ left: 16 })
            .onClick(() => {
              if (this.deleteTarget) {
                ResourceManager.deleteItem(this.deleteTarget);
                this.showDeleteConfirm = false;
                this.loadItems();
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
}
