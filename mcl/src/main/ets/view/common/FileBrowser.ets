/**
 * 文件浏览器组件
 * 移植自: FCLLibrary/browser/
 */
import { FileUtils } from '../../core/util/FileUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-FileBrowser';

/** 文件浏览器配置 */
export interface FileBrowserConfig {
  /** 初始路径 */
  initialPath?: string;
  /** 文件选择模式 */
  selectionMode: 'file' | 'directory' | 'multiple';
  /** 文件过滤 (扩展名) */
  fileFilter?: string[];
  /** 是否显示隐藏文件 */
  showHidden?: boolean;
  /** 标题 */
  title?: string;
}

/** 文件项 */
interface FileItem {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  sizeFormatted: string;
}

/** 面包屑 */
interface Breadcrumb {
  name: string;
  path: string;
}

@ComponentV2
export struct FileBrowser {
  @Param config: FileBrowserConfig = { selectionMode: 'file' };
  @Event onFileSelected?: (path: string) => void;
  @Event onFilesSelected?: (paths: string[]) => void;
  @Event onCancel?: () => void;

  @Local currentPath: string = '';
  @Local files: FileItem[] = [];
  @Local breadcrumbs: Breadcrumb[] = [];
  @Local selectedFiles: Set<string> = new Set();
  @Local isLoading: boolean = false;
  @Local errorMessage: string = '';
  @Local sortBy: 'name' | 'size' | 'type' = 'name';
  @Local sortAsc: boolean = true;

  aboutToAppear(): void {
    this.currentPath = this.config.initialPath ?? FileUtils.getMinecraftDir();
    this.loadDirectory();
  }

  loadDirectory(): void {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      if (!FileUtils.exists(this.currentPath)) {
        this.errorMessage = 'Directory not found';
        this.isLoading = false;
        return;
      }

      // 构建面包屑
      this.buildBreadcrumbs();

      // 列出文件
      const names = FileUtils.listFiles(this.currentPath);
      const items: FileItem[] = [];

      names.forEach(name => {
        // 隐藏文件过滤
        if (!this.config.showHidden && name.startsWith('.')) {
          return;
        }

        const fullPath = `${this.currentPath}/${name}`;
        const isDirectory = FileUtils.isDirectory(fullPath);
        const size = FileUtils.getSize(fullPath);

        // 扩展名过滤
        if (!isDirectory && this.config.fileFilter && this.config.fileFilter.length > 0) {
          const ext = name.split('.').pop()?.toLowerCase() ?? '';
          if (!this.config.fileFilter.includes(ext) && !this.config.fileFilter.includes(`.${ext}`)) {
            return;
          }
        }

        items.push({
          name,
          path: fullPath,
          isDirectory,
          size: size >= 0 ? size : 0,
          sizeFormatted: isDirectory ? '-' : FileUtils.formatSize(size >= 0 ? size : 0)
        });
      });

      // 排序
      this.sortFiles(items);
      this.files = items;

    } catch (err) {
      this.errorMessage = `Failed to load directory: ${err}`;
    } finally {
      this.isLoading = false;
    }
  }

  buildBreadcrumbs(): void {
    const parts = this.currentPath.split('/').filter(p => p.length > 0);
    this.breadcrumbs = [{ name: 'Root', path: '/' }];

    let accumulated = '';
    parts.forEach(part => {
      accumulated += `/${part}`;
      this.breadcrumbs.push({ name: part, path: accumulated });
    });
  }

  sortFiles(items: FileItem[]): void {
    // 目录优先
    const dirs = items.filter(f => f.isDirectory);
    const files = items.filter(f => !f.isDirectory);

    const sortFn = (a: FileItem, b: FileItem) => {
      let cmp = 0;
      if (this.sortBy === 'name') {
        cmp = a.name.localeCompare(b.name);
      } else if (this.sortBy === 'size') {
        cmp = a.size - b.size;
      }
      return this.sortAsc ? cmp : -cmp;
    };

    dirs.sort(sortFn);
    files.sort(sortFn);

    this.files = [...dirs, ...files];
  }

  build() {
    Column() {
      // 标题栏
      this.buildTitleBar();

      // 面包屑
      this.buildBreadcrumbNav();

      // 文件列表
      if (this.isLoading) {
        LoadingProgress().width(32).height(32).color('#E94560').margin({ top: 32 })
      } else if (this.errorMessage) {
        Text(this.errorMessage).fontSize(14).fontColor('#FF5252').margin({ top: 16 })
      } else {
        this.buildFileList();
      }

      // 底部按钮
      this.buildBottomBar();
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
  }

  @Builder
  buildTitleBar() {
    Row() {
      Button('← Back')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('transparent')
        .onClick(() => {
          const parentPath = this.currentPath.substring(0, this.currentPath.lastIndexOf('/'));
          if (parentPath) {
            this.currentPath = parentPath;
            this.loadDirectory();
          }
        })

      Text(this.config.title ?? 'File Browser')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // 排序切换
      Button(this.sortAsc ? '↑' : '↓')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('transparent')
        .onClick(() => { this.sortAsc = !this.sortAsc; this.loadDirectory(); })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213E')
  }

  @Builder
  buildBreadcrumbNav() {
    Scroll() {
      Row() {
        ForEach(this.breadcrumbs, (crumb: Breadcrumb, index: number) => {
          Row() {
            Text(crumb.name)
              .fontSize(12)
              .fontColor(index === this.breadcrumbs.length - 1 ? '#E94560' : '#999999')
              .onClick(() => {
                this.currentPath = crumb.path;
                this.loadDirectory();
              })

            if (index < this.breadcrumbs.length - 1) {
              Text(' / ')
                .fontSize(12)
                .fontColor('#555555')
            }
          }
          .flexShrink(0)
        })
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .backgroundColor('#0D1B2A')
  }

  @Builder
  buildFileList() {
    List() {
      ForEach(this.files, (file: FileItem) => {
        ListItem() {
          Row() {
            // 图标
            Text(file.isDirectory ? '📁' : '📄')
              .fontSize(20)
              .margin({ right: 12 })

            // 信息
            Column() {
              Text(file.name)
                .fontSize(15)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(file.sizeFormatted)
                .fontSize(12)
                .fontColor('#999999')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 多选模式
            if (this.config.selectionMode === 'multiple') {
              Checkbox()
                .select(this.selectedFiles.has(file.path))
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.selectedFiles.add(file.path);
                  } else {
                    this.selectedFiles.delete(file.path);
                  }
                })
            }
          }
          .width('100%')
          .padding(12)
          .onClick(() => {
            if (file.isDirectory) {
              this.currentPath = file.path;
              this.loadDirectory();
            } else {
              this.handleFileClick(file);
            }
          })
        }
      })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
  }

  @Builder
  buildBottomBar() {
    Row() {
      if (this.config.selectionMode === 'multiple' && this.selectedFiles.size > 0) {
        Text(`${this.selectedFiles.size} selected`)
          .fontSize(14)
          .fontColor('#4CAF50')
          .layoutWeight(1)

        Button('Confirm Selection')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#E94560')
          .borderRadius(8)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => {
            if (this.onFilesSelected) {
              this.onFilesSelected(Array.from(this.selectedFiles));
            }
          })
      } else {
        Text('Tap folder to enter, tap file to select')
          .fontSize(12)
          .fontColor('#666666')
          .layoutWeight(1)
      }

      Button('Cancel')
        .fontSize(14)
        .fontColor('#999999')
        .backgroundColor('transparent')
        .onClick(() => {
          if (this.onCancel) this.onCancel();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
  }

  handleFileClick(file: FileItem): void {
    if (this.config.selectionMode === 'file' && this.onFileSelected) {
      this.onFileSelected(file.path);
    } else if (this.config.selectionMode === 'multiple') {
      // 点击切换选择状态
      if (this.selectedFiles.has(file.path)) {
        this.selectedFiles.delete(file.path);
      } else {
        this.selectedFiles.add(file.path);
      }
    } else if (this.config.selectionMode === 'directory' && file.isDirectory && this.onFileSelected) {
      this.onFileSelected(file.path);
    }
  }
}
