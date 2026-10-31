/**
 * 文件下载管理器
 * 移植自: FCLCore 的下载服务逻辑
 * 使用 HarmonyOS @ohos.request 系统级下载 API
 */
import { request, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../../common/AppContext';

const TAG = 'FCL-DownloadManager';

/** 下载进度回调 */
export type DownloadProgressCallback = (receivedSize: number, totalSize: number) => void;

/** 下载任务 */
export class DownloadTask {
  readonly url: string;
  readonly filePath: string;
  readonly sha1?: string;
  readonly size?: number;
  private _progress: number = 0;
  private _status: DownloadStatus = DownloadStatus.PENDING;

  constructor(url: string, filePath: string, sha1?: string, size?: number) {
    this.url = url;
    this.filePath = filePath;
    this.sha1 = sha1;
    this.size = size;
  }

  get progress(): number {
    return this._progress;
  }

  get status(): DownloadStatus {
    return this._status;
  }

  set status(value: DownloadStatus) {
    this._status = value;
  }

  set progress(value: number) {
    this._progress = value;
  }
}

/** 下载状态 */
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

/** 下载结果 */
export class DownloadResult {
  readonly success: boolean;
  readonly task: DownloadTask;
  readonly error?: string;

  constructor(success: boolean, task: DownloadTask, error?: string) {
    this.success = success;
    this.task = task;
    this.error = error;
  }
}

/**
 * 下载管理器 - 管理多任务并发下载
 */
export class DownloadManager {
  private tasks: DownloadTask[] = [];
  private activeDownloads: Map<string, request.DownloadTask> = new Map();
  private maxConcurrency: number;
  private onProgress?: DownloadProgressCallback;
  private onTaskComplete?: (result: DownloadResult) => void;
  private onAllComplete?: (results: DownloadResult[]) => void;
  private completedCount: number = 0;

  constructor(maxConcurrency: number = 4) {
    this.maxConcurrency = maxConcurrency;
  }

  /** 设置进度回调 */
  setOnProgress(callback: DownloadProgressCallback): void {
    this.onProgress = callback;
  }

  /** 设置单个任务完成回调 */
  setOnTaskComplete(callback: (result: DownloadResult) => void): void {
    this.onTaskComplete = callback;
  }

  /** 设置全部完成回调 */
  setOnAllComplete(callback: (results: DownloadResult[]) => void): void {
    this.onAllComplete = callback;
  }

  /** 添加下载任务 */
  addTask(task: DownloadTask): void {
    this.tasks.push(task);
  }

  /** 添加多个下载任务 */
  addTasks(tasks: DownloadTask[]): void {
    this.tasks.push(...tasks);
  }

  /** 开始下载所有任务 (队列模式) */
  async startAll(): Promise<DownloadResult[]> {
    const results: DownloadResult[] = [];
    this.completedCount = 0;

    // 使用队列控制并发
    const queue = [...this.tasks];
    const running: Promise<void>[] = [];

    for (let i = 0; i < Math.min(this.maxConcurrency, queue.length); i++) {
      running.push(this.processQueue(queue, results));
    }

    await Promise.all(running);

    if (this.onAllComplete) {
      this.onAllComplete(results);
    }

    return results;
  }

  /** 处理下载队列 */
  private async processQueue(queue: DownloadTask[], results: DownloadResult[]): Promise<void> {
    while (queue.length > 0) {
      const task = queue.shift();
      if (!task) {
        break;
      }

      const result = await this.downloadSingle(task);
      results.push(result);
      this.completedCount++;

      if (this.onTaskComplete) {
        this.onTaskComplete(result);
      }
    }
  }

  /** 下载单个文件 */
  private async downloadSingle(task: DownloadTask): Promise<DownloadResult> {
    try {
      task.status = DownloadStatus.DOWNLOADING;
      hilog.info(0x0000, TAG, `Downloading: ${task.url}`);

      const downloadTask = await request.downloadFile(AppContext.context, {
        url: task.url,
        filePath: task.filePath,
        background: false,
        enableMetered: true,
        enableRoaming: true
      });

      return new Promise<DownloadResult>((resolve) => {
        downloadTask.on('progress', (receivedSize: number, totalSize: number) => {
          if (totalSize > 0) {
            task.progress = receivedSize / totalSize;
          }
          if (this.onProgress) {
            this.onProgress(receivedSize, totalSize);
          }
        });

        downloadTask.on('complete', () => {
          task.status = DownloadStatus.COMPLETED;
          task.progress = 1;
          hilog.info(0x0000, TAG, `Download complete: ${task.url}`);
          resolve(new DownloadResult(true, task));
        });

        downloadTask.on('fail', (err: number) => {
          task.status = DownloadStatus.FAILED;
          hilog.error(0x0000, TAG, `Download failed: ${task.url}, code=${err}`);
          resolve(new DownloadResult(false, task, `[${err}] download failed`));
        });
      });
    } catch (err) {
      const error = err as BusinessError;
      task.status = DownloadStatus.FAILED;
      hilog.error(0x0000, TAG, `Download error: ${task.url}, ${error.message}`);
      return new DownloadResult(false, task, error.message);
    }
  }

  /** 取消所有下载 */
  cancelAll(): void {
    this.activeDownloads.forEach((task, key) => {
      try {
        task.delete();
      } catch (err) {
        hilog.warn(0x0000, TAG, `Failed to cancel download: ${key}`);
      }
    });
    this.activeDownloads.clear();
    this.tasks.forEach(t => {
      if (t.status === DownloadStatus.DOWNLOADING) {
        t.status = DownloadStatus.CANCELLED;
      }
    });
  }

  /** 获取总进度 */
  getTotalProgress(): number {
    if (this.tasks.length === 0) {
      return 0;
    }
    const totalProgress = this.tasks.reduce((sum, t) => sum + t.progress, 0);
    return totalProgress / this.tasks.length;
  }

  /** 获取已完成数量 */
  getCompletedCount(): number {
    return this.completedCount;
  }

  /** 获取总任务数量 */
  getTotalCount(): number {
    return this.tasks.length;
  }

  /** 清理已完成/失败的任务 */
  clearCompleted(): void {
    this.tasks = this.tasks.filter(
      t => t.status === DownloadStatus.PENDING || t.status === DownloadStatus.DOWNLOADING
    );
  }
}
