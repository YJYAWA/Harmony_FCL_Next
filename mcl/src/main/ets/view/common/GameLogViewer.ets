/**
 * 游戏日志查看器
 * 移植自: FCL 中的日志导出和显示功能
 * 显示 Minecraft JVM 实时输出
 */
import { GameLauncherService, GameProcessCallbacks } from '../../service/GameLauncherService';
import { FileUtils } from '../../core/util/FileUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-GameLogViewer';

@ComponentV2
export struct GameLogViewer {
  @Local _autoScroll: boolean = true;
  @Event onClose?: () => void;

  @Local logLines: string[] = [];
  @Local maxLines: number = 1000;
  @Local filterText: string = '';
  @Local filteredLines: string[] = [];
  @Local showTimestamps: boolean = true;
  @Local showLogLevels: boolean = true;
  @Local isRunning: boolean = false;
  @Local exportPath: string = '';

  private launcher: GameLauncherService = GameLauncherService.getInstance();

  aboutToAppear(): void {
    this.isRunning = this.launcher.isRunning;

    // 注册日志回调
    const callbacks: GameProcessCallbacks = {
      onOutput: (line: string): void => {
        this.addLine(line);
      },
      onExit: (exitCode: number): void => {
        this.addLine(`[FCL] Game exited with code ${exitCode}`);
        this.isRunning = false;
      },
      onError: (error: string): void => {
        this.addLine(`[FCL/ERROR] ${error}`);
      }
    };
    this.launcher.setCallbacks(callbacks);

    // 加载已有日志
    const state = this.launcher.state;
    if (state.logLines) {
      this.logLines = [...state.logLines];
      this.applyFilter();
    }
  }

  private addLine(line: string): void {
    const timestamped = this.showTimestamps ?
      `[${new Date().toLocaleTimeString()}] ${line}` : line;
    this.logLines.push(timestamped);

    // 限制内存占用
    if (this.logLines.length > this.maxLines) {
      this.logLines = this.logLines.slice(-500);
    }

    this.applyFilter();
  }

  private applyFilter(): void {
    if (!this.filterText.trim()) {
      this.filteredLines = [...this.logLines];
      return;
    }

    const q = this.filterText.toLowerCase();
    this.filteredLines = this.logLines.filter(line =>
      line.toLowerCase().includes(q)
    );
  }

  build() {
    Column() {
      // 顶部工具栏
      this.buildToolbar();

      // 日志内容
      List() {
        ForEach(this.filteredLines, (line: string) => {
          ListItem() {
            Text(line)
              .fontSize(11)
              .fontColor(this.getLineColor(line))
              .fontFamily('monospace')
              .padding({ left: 8, right: 8, top: 1, bottom: 1 })
              .maxLines(20)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        })
      }
      .layoutWeight(1)
      .backgroundColor('#0A0A1A')
      .scrollBar(BarState.Auto)
      .onScrollIndex((start: number) => {
        // 如果用户在底部, 启用自动滚动
      })

      // 底部操作栏
      this.buildBottomBar();
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildToolbar() {
    Row() {
      Text('Game Console')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')

      if (this.isRunning) {
        Text(' ● Running')
          .fontSize(12).fontColor('#4CAF50').margin({ left: 8 })
      }

      Blank()

      // 过滤输入
      TextInput({ placeholder: 'Filter...', text: this.filterText })
        .fontSize(12).fontColor('#FFFFFF').backgroundColor('#16213E')
        .borderRadius(6).padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .width(120)
        .onChange((value: string) => {
          this.filterText = value;
          this.applyFilter();
        })

      // 功能按钮
      this.buildToolButton('Export', () => this.exportLogs())
      this.buildToolButton('Clear', () => {
        this.logLines = [];
        this.applyFilter();
      })

      if (this.onClose) {
        this.buildToolButton('Close', () => { if (this.onClose) this.onClose(); })
      }
    }
    .width('100%').padding(8).backgroundColor('#16213E')
  }

  @Builder
  buildToolButton(label: string, action: () => void) {
    Text(label)
      .fontSize(11).fontColor('#999999')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(4)
      .margin({ left: 4 })
      .onClick(action)
  }

  @Builder
  buildBottomBar() {
    Row() {
      Text(`${this.filteredLines.length} lines`)
        .fontSize(11).fontColor('#666666').layoutWeight(1)

      Text(this._autoScroll ? 'Auto-scroll: ON' : 'Auto-scroll: OFF')
        .fontSize(11).fontColor('#666666')
        .margin({ right: 12 })
        .onClick(() => { this._autoScroll = !this._autoScroll; })

      if (this.getErrorCount() > 0) {
        Text(`${this.getErrorCount()} errors`)
          .fontSize(11).fontColor('#FF5252')
      }
    }
    .width('100%').padding(8).backgroundColor('#0D1B2A')
  }

  getLineColor(line: string): string {
    if (line.includes('ERROR') || line.includes('FATAL')) {
      return '#FF5252';
    }
    if (line.includes('WARN')) {
      return '#FF9800';
    }
    if (line.includes('INFO')) {
      return '#4CAF50';
    }
    if (line.includes('DEBUG')) {
      return '#2196F3';
    }
    if (line.startsWith('[FCL')) {
      return '#E94560';
    }
    return '#CCCCCC';
  }

  getErrorCount(): number {
    return this.filteredLines.filter(l =>
      l.includes('ERROR') || l.includes('Exception') || l.includes('FATAL')
    ).length;
  }

  exportLogs(): void {
    const path = `${FileUtils.getMinecraftDir()}/logs/game-${Date.now()}.log`;
    const content = this.logLines.join('\n');
    if (FileUtils.writeText(path, content)) {
      this.exportPath = path;
      hilog.info(0x0000, TAG, `Logs exported to ${path}`);
    }
  }
}
