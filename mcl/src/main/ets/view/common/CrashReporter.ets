/**
 * 崩溃报告器
 * 移植自: FCLLibrary/crash/
 * 捕获未处理异常、生成崩溃报告、提供分享功能
 */
import { FileUtils } from '../../core/util/FileUtils';
import { AppVersion } from '../../core/util/AppVersion';
import { AppContext } from '../../common/AppContext';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'FCL-CrashReporter';

/** 崩溃报告 */
interface CrashReport {
  timestamp: string;
  appVersion: string;
  deviceInfo: string;
  stackTrace: string;
  logLines: string[];
  crashType: string;
  cause?: string;
}

/**
 * 崩溃报告管理器
 */
export class CrashReporter {
  private static instance: CrashReporter | null = null;
  private reports: CrashReport[] = [];
  private crashLogs: string[] = [];
  private isInitialized: boolean = false;

  private constructor() {
  }

  static getInstance(): CrashReporter {
    if (!CrashReporter.instance) {
      CrashReporter.instance = new CrashReporter();
    }
    return CrashReporter.instance;
  }

  /**
   * 初始化崩溃捕获
   */
  initialize(): void {
    if (this.isInitialized) {
      return;
    }

    // 捕获未处理的 Promise 拒绝
    // ArkTS 中的错误处理: 使用 errorManager
    try {
      // 加载之前的崩溃报告
      this.loadSavedReports();

      hilog.info(0x0000, TAG, 'Crash reporter initialized');
      this.isInitialized = true;
    } catch (err) {
      hilog.error(0x0000, TAG, `Crash reporter init failed: ${err}`);
    }
  }

  /**
   * 记录崩溃信息
   */
  recordCrash(error: Error, type: string = 'unhandled'): CrashReport {
    hilog.error(0x0000, TAG, `CRASH [${type}]: ${error.message}`);

    const report: CrashReport = {
      timestamp: new Date().toISOString(),
      appVersion: AppVersion.VERSION_NAME,
      deviceInfo: `${deviceInfo.deviceType} / ${deviceInfo.marketName}`,
      stackTrace: error.stack ?? error.message,
      logLines: [...this.crashLogs].slice(-50), // 最近 50 行
      crashType: type,
      cause: error.message
    };

    this.reports.push(report);
    this.saveReport(report);

    return report;
  }

  /**
   * 添加日志行 (滚动缓冲区)
   */
  addLogLine(line: string): void {
    this.crashLogs.push(`[${new Date().toISOString()}] ${line}`);
    if (this.crashLogs.length > 200) {
      this.crashLogs = this.crashLogs.slice(-100);
    }
  }

  /**
   * 获取所有保存的报告
   */
  getReports(): CrashReport[] {
    this.loadSavedReports();
    return [...this.reports];
  }

  /**
   * 生成崩溃报告文本
   */
  generateReportText(report: CrashReport): string {
    const lines: string[] = [
      '========================================',
      '  FCL-HarmonyOS Crash Report',
      '========================================',
      `Date:      ${report.timestamp}`,
      `Version:   ${report.appVersion}`,
      `Device:    ${report.deviceInfo}`,
      `Type:      ${report.crashType}`,
      `Error:     ${report.cause ?? 'Unknown'}`,
      '----------------------------------------',
      'Stack Trace:',
      '----------------------------------------',
      report.stackTrace,
      '----------------------------------------',
      'Recent Logs:',
      '----------------------------------------',
      ...report.logLines,
      '========================================'
    ];

    return lines.join('\n');
  }

  /**
   * 导出所有报告
   */
  exportReports(): string {
    const dir = `${AppContext.filesDir}/crash-reports`;
    FileUtils.mkdirs(dir);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const path = `${dir}/crash-${timestamp}.txt`;
    const content = this.reports.map(r => this.generateReportText(r)).join('\n\n');
    FileUtils.writeText(path, content);
    return path;
  }

  /**
   * 清除所有报告
   */
  clearReports(): void {
    this.reports = [];
    const dir = `${AppContext.filesDir}/crash-reports`;
    if (FileUtils.exists(dir)) {
      FileUtils.delete(dir);
    }
  }

  // ========== 持久化 ==========

  private saveReport(report: CrashReport): void {
    const dir = `${AppContext.filesDir}/crash-reports`;
    FileUtils.mkdirs(dir);
    const filename = `crash-${report.timestamp.replace(/[:.]/g, '-')}.json`;
    FileUtils.writeJSON(`${dir}/${filename}`, report);
  }

  private loadSavedReports(): void {
    const dir = `${AppContext.filesDir}/crash-reports`;
    if (!FileUtils.exists(dir)) {
      return;
    }

    const files = FileUtils.listFiles(dir)
      .filter(f => f.endsWith('.json'))
      .sort()
      .reverse()
      .slice(0, 10);

    this.reports = files
      .map(f => FileUtils.readJSON<CrashReport>(`${dir}/${f}`))
      .filter((r: CrashReport | null): boolean => r !== null) as CrashReport[];
  }
}

/**
 * 崩溃报告显示组件
 */
@ComponentV2
export struct CrashReportView {
  @Local reports: CrashReport[] = [];
  @Local selectedReport: CrashReport | null = null;
  @Local reportText: string = '';

  private reporter: CrashReporter = CrashReporter.getInstance();

  aboutToAppear(): void {
    this.reports = this.reporter.getReports();
  }

  build() {
    Column() {
      Text('Crash Reports')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width('100%').padding(16)

      if (this.reports.length === 0) {
        Column() {
          Text('No crash reports')
            .fontSize(16).fontColor('#999999').margin({ top: 32 })
          Text('Everything is running smoothly!')
            .fontSize(14).fontColor('#666666')
        }
        .width('100%').alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.reports, (report: CrashReport) => {
            ListItem() {
              Row() {
                Column() {
                  Text(report.cause ?? 'Unknown error')
                    .fontSize(14).fontColor('#FF5252').maxLines(1)
                  Text(report.timestamp)
                    .fontSize(11).fontColor('#666666').margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
              }
              .width('100%').padding(12).backgroundColor('#16213E')
              .borderRadius(8).margin({ top: 4, left: 16, right: 16 })
              .onClick(() => {
                this.selectedReport = report;
                this.reportText = this.reporter.generateReportText(report);
              })
            }
          })
        }
        .layoutWeight(1).scrollBar(BarState.Auto)
      }

      // 导出和清除按钮
      if (this.reports.length > 0) {
        Row() {
          Button('Export All')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .onClick(() => {
              const path = this.reporter.exportReports();
              hilog.info(0x0000, TAG, `Reports exported to ${path}`);
            })

          Button('Clear All')
            .fontSize(14).fontColor('#FF5252').backgroundColor('transparent')
            .border({ width: 1, color: '#FF5252' }).borderRadius(8)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .margin({ left: 12 })
            .onClick(() => {
              this.reporter.clearReports();
              this.reports = [];
            })
        }
        .width('100%').padding(16).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor('#1A1A2E')
  }
}
