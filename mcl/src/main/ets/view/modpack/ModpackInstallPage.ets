/**
 * 整合包安装页面
 *
 * 对应上游 FCL 的 ui/download/modpack/ModpackInstaller.java + ModpackUrlDialog.java
 * （本项目只做本地 zip 安装；远程整合包下载需要各平台 API，暂不实现）。
 *
 * 流程：系统文件选择器选 .zip → 输入实例名 → 安装（带阶段进度）
 */
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { ModpackInstaller, ModpackProgress, ModpackInstallResult } from '../../core/modpack/ModpackInstaller';
import { FileUtils } from '../../core/util/FileUtils';

@ComponentV2
export struct ModpackInstallPage {
  @Local selectedFile: string = '';
  @Local selectedName: string = '';
  @Local installing: boolean = false;
  @Local stage: string = '';
  @Local progress: number = 0;
  @Local resultMessage: string = '';
  @Local success: boolean = false;

  aboutToAppear(): void {
    this.selectedName = `Modpack_${new Date().toISOString().slice(0, 10)}`;
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('Install Modpack')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        Blank()
        Text('Local .zip')
          .fontSize(12).fontColor('#999999')
      }
      .width('100%').padding(16)

      Scroll() {
        Column() {
          // 文件选择
          this.buildFilePicker()

          // 实例名
          this.buildNameInput()

          // 格式说明
          this.buildFormatHint()

          // 安装进度
          if (this.installing || this.progress > 0) {
            this.buildProgress()
          }

          // 结果
          if (this.resultMessage.length > 0) {
            this.buildResult()
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor('#1A1A2E')
  }

  @Builder
  buildFilePicker() {
    Column() {
      Text('Modpack file')
        .fontSize(13).fontColor('#999999')
        .margin({ bottom: 8 })

      Row() {
        Text(this.selectedFile.length > 0 ? this.selectedFile : 'No file selected')
          .fontSize(13)
          .fontColor(this.selectedFile.length > 0 ? '#FFFFFF' : '#666666')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ right: 12 })

        Button('Choose')
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(8).padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .enabled(!this.installing)
          .onClick(() => {
            this.pickFile();
          })
      }
      .width('100%').padding(14)
      .backgroundColor('#16213E').borderRadius(10)
    }
    .width('100%').margin({ bottom: 16 })
  }

  @Builder
  buildNameInput() {
    Column() {
      Text('Instance name')
        .fontSize(13).fontColor('#999999')
        .margin({ bottom: 8 })

      TextInput({ placeholder: 'My Modpack', text: this.selectedName })
        .fontSize(14).fontColor('#FFFFFF')
        .backgroundColor('#16213E').borderRadius(8)
        .padding(12)
        .enabled(!this.installing)
        .onChange((value: string) => {
          this.selectedName = value;
        })

      Button('Install')
        .fontSize(15).fontColor('#FFFFFF').backgroundColor('#E94560')
        .borderRadius(10).padding({ left: 24, right: 24, top: 12, bottom: 12 })
        .margin({ top: 16 })
        .width('100%')
        .enabled(!this.installing && this.selectedFile.length > 0)
        .onClick(() => {
          this.install();
        })
    }
    .width('100%').margin({ bottom: 16 })
  }

  @Builder
  buildFormatHint() {
    Column() {
      Text('Supported formats')
        .fontSize(13).fontColor('#999999')
        .margin({ bottom: 6 })
      Text('MCBBS · CurseForge · Modrinth · HMCL · MultiMC\n手工整合包（zip 内含 .minecraft 目录）')
        .fontSize(12).fontColor('#666666')
        .lineHeight(18)
    }
    .width('100%').padding(14)
    .backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  @Builder
  buildProgress() {
    Column() {
      Text(this.stage)
        .fontSize(13).fontColor('#CCCCCC')
        .margin({ bottom: 8 })
      Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
        .width('100%').height(6).color('#E94560')
    }
    .width('100%').padding(14)
    .backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  @Builder
  buildResult() {
    Column() {
      Text(this.success ? 'Installed' : 'Failed')
        .fontSize(15).fontWeight(FontWeight.Bold)
        .fontColor(this.success ? '#4CAF50' : '#FF5252')
        .margin({ bottom: 6 })
      Text(this.resultMessage)
        .fontSize(13).fontColor('#CCCCCC')
    }
    .width('100%').padding(14)
    .backgroundColor('#16213E').borderRadius(10)
    .margin({ bottom: 16 })
  }

  /** 用系统文件选择器挑 zip（鸿蒙下用户显式授权，不需要额外权限） */
  private async pickFile(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.zip', '.mrpack'];
      const dp = new picker.DocumentViewPicker(ctx);
      const uris = await dp.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      // picker 返回 file://docs/... uri，需要拷进沙箱才能被 zlib 读取
      const name = this.basenameFromUri(uri);
      const tempPath = `${ctx.tempDir}/fcl_modpack_src_${Date.now()}_${name}`;
      const f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(f.fd, tempPath);
      } finally {
        fs.closeSync(f);
      }
      this.selectedFile = name;
      this.pendingPath = tempPath;
      if (this.selectedName.length === 0 || this.selectedName.startsWith('Modpack_')) {
        this.selectedName = name.replace(/\.(zip|mrpack)$/i, '');
      }
    } catch (err) {
      promptAction.showToast({ message: `选择文件失败: ${err}` });
    }
  }

  /** 选中的 zip 在沙箱内的真实路径 */
  private pendingPath: string = '';

  /** 执行安装 */
  private async install(): Promise<void> {
    if (this.pendingPath.length === 0) {
      promptAction.showToast({ message: '请先选择整合包文件' });
      return;
    }
    const name = this.selectedName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入实例名' });
      return;
    }

    this.installing = true;
    this.progress = 0;
    this.stage = '准备中...';
    this.resultMessage = '';
    this.success = false;

    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: ModpackInstallResult = await ModpackInstaller.installFromZip(
        ctx, this.pendingPath, name,
        (p: ModpackProgress) => {
          this.stage = p.message;
          this.progress = Math.round(p.progress * 100);
        });
      this.success = result.success;
      if (result.success) {
        this.resultMessage = `整合包 "${result.name}" 安装完成，版本 id: ${result.versionId}`;
        promptAction.showToast({ message: '整合包安装完成' });
      } else {
        this.resultMessage = result.error ?? '未知错误';
      }
    } catch (err) {
      this.success = false;
      this.resultMessage = `${err}`;
    } finally {
      this.installing = false;
      // 清理临时 zip
      if (this.pendingPath.length > 0) {
        FileUtils.delete(this.pendingPath);
      }
    }
  }

  private basenameFromUri(uri: string): string {
    let u = uri;
    const q = u.indexOf('?');
    if (q >= 0) {
      u = u.substring(0, q);
    }
    const slash = u.lastIndexOf('/');
    let name = slash >= 0 ? u.substring(slash + 1) : u;
    try {
      name = decodeURIComponent(name);
    } catch (err) {
      // 保留原值
    }
    return name;
  }
}
