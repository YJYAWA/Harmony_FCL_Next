import { httpGet } from '../util/HttpUtils';
/**
 * Minecraft 版本管理器
 * 移植自: FCLCore 的 DefaultGameBuilder + VersionList
 *
 * 负责:
 * 1. 获取可用 Minecraft 版本列表
 * 2. 下载和安装游戏版本
 * 3. 管理已安装版本
 * 4. 模组加载器安装 (Fabric/Forge/NeoForge/OptiFine)
 */
import { GameVersion, VersionType, Library, AssetIndex, AssetObject, JavaVersion, LibraryDownloads, LibraryRule } from './GameTypes';
import { DownloadManager, DownloadTask, DownloadResult } from '../download/DownloadManager';
import { DownloadProvider, RemoteVersion } from '../download/DownloadProvider';
import { FileUtils } from '../util/FileUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-VersionManager';

/** 版本安装进度 */
export interface InstallProgress {
  stage: 'preparing' | 'downloading' | 'installing' | 'complete' | 'error';
  totalFiles: number;
  completedFiles: number;
  currentFile: string;
  totalSize: number;
  downloadedSize: number;
  error?: string;
}

/** 版本安装回调 */
export interface InstallCallbacks {
  onProgress?: (progress: InstallProgress) => void;
  onComplete?: () => void;
  onError?: (error: string) => void;
}

/**
 * 版本管理器
 */
export class VersionManager {
  private provider: DownloadProvider;

  constructor(provider: DownloadProvider) {
    this.provider = provider;
  }

  /** 获取远程版本列表 */
  async getRemoteVersions(): Promise<RemoteVersion[]> {
    const url = this.provider.getVersionListURL();
    try {
      const response = await httpGet(url);
      const data = await response.json() as Record<string, Object>;
      const versions = data['versions'] as Array<Record<string, string>>;

      const result: RemoteVersion[] = [];
      for (let i = 0; i < (versions ?? []).length; i++) {
        const v = (versions ?? [])[i];
        const rv: RemoteVersion = {
          version: v['id'] ?? '',
          type: (v['type'] ?? 'release') as VersionType,
          releaseTime: v['releaseTime'] ?? '',
          url: v['url'] ?? ''
        };
        result.push(rv);
      }
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to fetch version list: ${err}`);
      return [];
    }
  }

  /** 获取远程版本的详细 JSON 信息 */
  async getVersionDetail(versionId: string): Promise<GameVersion | null> {
    // 先查缓存
    const cached = FileUtils.readJSON<GameVersion>(
      `${FileUtils.getVersionsDir()}/${versionId}/${versionId}.json`
    );
    if (cached) {
      return cached;
    }

    // 从远程获取版本列表，找到对应版本的 URL
    const versions = await this.getRemoteVersions();
    const versionInfo = versions.find(v => v.version === versionId);
    if (!versionInfo) {
      return null;
    }

    // 获取版本详情 JSON
    const url = this.provider.injectURL(versionInfo.url);
    try {
      const response = await httpGet(url);
      const data = await response.json() as Record<string, Object>;

      const gv: GameVersion = {
        id: data['id'] as string ?? versionId,
        type: (data['type'] as VersionType) ?? VersionType.RELEASE,
        mainClass: data['mainClass'] as string ?? '',
        arguments: {
          game: this.extractStringArray(data, 'arguments.game'),
          jvm: this.extractStringArray(data, 'arguments.jvm')
        },
        libraries: this.parseLibraries(data['libraries']),
        assetIndex: data['assetIndex'] as AssetIndex,
        javaVersion: data['javaVersion'] as JavaVersion,
        releaseTime: data['releaseTime'] as string ?? ''
      };
      return gv;
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to fetch version detail: ${err}`);
      return null;
    }
  }

  /** 安装游戏版本 */
  async installVersion(versionId: string, callbacks?: InstallCallbacks): Promise<void> {
    callbacks?.onProgress?.({
      stage: 'preparing',
      totalFiles: 0,
      completedFiles: 0,
      currentFile: 'Preparing...',
      totalSize: 0,
      downloadedSize: 0
    });

    try {
      // 获取版本详情
      const version = await this.getVersionDetail(versionId);
      if (!version) {
        throw new Error(`Version ${versionId} not found`);
      }

      // 创建目录
      const versionDir = `${FileUtils.getVersionsDir()}/${versionId}`;
      FileUtils.mkdirs(versionDir);

      // 保存版本 JSON
      const versions = await this.getRemoteVersions();
      const versionInfo = versions.find(v => v.version === versionId);
      if (versionInfo) {
        const detailURL = this.provider.injectURL(versionInfo.url);
        const response = await httpGet(detailURL);
        const jsonData = await response.text();
        FileUtils.writeText(`${versionDir}/${versionId}.json`, jsonData);
      }

      // 收集需要下载的文件
      const tasks: DownloadTask[] = [];

      // 1. 下载客户端 JAR
      const jarUrl = this.provider.injectURL(
        `https://launcher.mojang.com/v1/objects/${versionId}/client.jar`
      );
      tasks.push(new DownloadTask(
        jarUrl,
        `${versionDir}/${versionId}.jar`
      ));

      // 2. 下载依赖库
      for (const lib of version.libraries) {
        if (!lib.downloads?.artifact) {
          continue;
        }

        const art = lib.downloads.artifact;
        const libUrl = this.provider.injectURL(art.url);
        const libPath = `${FileUtils.getLibrariesDir()}/${art.path}`;

        tasks.push(new DownloadTask(libUrl, libPath, art.sha1, art.size));
      }

      // 3. 下载资源索引
      if (version.assetIndex) {
        const assetUrl = this.provider.injectURL(version.assetIndex.url);
        const indexPath = `${FileUtils.getAssetsDir()}/indexes/${version.assetIndex.id}.json`;
        tasks.push(new DownloadTask(assetUrl, indexPath, version.assetIndex.sha1, version.assetIndex.size));
      }

      // 开始下载
      callbacks?.onProgress?.({
        stage: 'downloading',
        totalFiles: tasks.length,
        completedFiles: 0,
        currentFile: '',
        totalSize: tasks.reduce((sum, t) => sum + (t.size ?? 0), 0),
        downloadedSize: 0
      });

      const downloader = new DownloadManager(this.provider.getConcurrency());
      downloader.addTasks(tasks);

      let completedFiles = 0;
      downloader.setOnTaskComplete((result: DownloadResult) => {
        completedFiles++;
        callbacks?.onProgress?.({
          stage: 'downloading',
          totalFiles: tasks.length,
          completedFiles,
          currentFile: result.task.url,
          totalSize: tasks.reduce((sum, t) => sum + (t.size ?? 0), 0),
          downloadedSize: 0
        });
      });

      const results = await downloader.startAll();
      const failed = results.filter(r => !r.success);

      if (failed.length > 0) {
        throw new Error(`${failed.length} file(s) failed to download`);
      }

      // 下载资源文件
      await this.downloadAssets(version, callbacks);

      callbacks?.onProgress?.({
        stage: 'complete',
        totalFiles: tasks.length,
        completedFiles: tasks.length,
        currentFile: 'Done',
        totalSize: 0,
        downloadedSize: 0
      });
      callbacks?.onComplete?.();

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      callbacks?.onProgress?.({
        stage: 'error',
        totalFiles: 0,
        completedFiles: 0,
        currentFile: '',
        totalSize: 0,
        downloadedSize: 0,
        error: errorMsg
      });
      callbacks?.onError?.(errorMsg);
    }
  }

  /** 下载资源文件 */
  private async downloadAssets(version: GameVersion, callbacks?: InstallCallbacks): Promise<void> {
    if (!version.assetIndex) {
      return;
    }

    const indexPath = `${FileUtils.getAssetsDir()}/indexes/${version.assetIndex.id}.json`;
    const indexData = FileUtils.readJSON<Record<string, Object>>(indexPath);
    if (!indexData) {
      return;
    }

    const objects = indexData['objects'] as Record<string, AssetObject> | undefined;
    if (!objects) {
      return;
    }

    const tasks: DownloadTask[] = [];
    for (const entry of Object.entries(objects)) {
      const name = entry[0];
      const obj = entry[1];
      const prefix = obj.hash.substring(0, 2);
      const assetUrl = this.provider.injectURL(
        `${this.provider.getAssetBaseURL()}${prefix}/${obj.hash}`
      );
      const assetPath = `${FileUtils.getAssetsDir()}/objects/${prefix}/${obj.hash}`;
      tasks.push(new DownloadTask(assetUrl, assetPath, obj.hash, obj.size));
    }

    const downloader = new DownloadManager(this.provider.getConcurrency());
    downloader.addTasks(tasks);
    await downloader.startAll();
  }

  /** 获取已安装版本列表 */
  getInstalledVersions(): string[] {
    const versionsDir = FileUtils.getVersionsDir();
    const dirs = FileUtils.listFiles(versionsDir);
    return dirs.filter(d => {
      const path = `${versionsDir}/${d}`;
      return FileUtils.isDirectory(path) &&
        FileUtils.exists(`${path}/${d}.json`) &&
        FileUtils.exists(`${path}/${d}.jar`);
    });
  }

  /** 检查版本是否已安装 */
  isVersionInstalled(versionId: string): boolean {
    const dir = `${FileUtils.getVersionsDir()}/${versionId}`;
    return FileUtils.exists(`${dir}/${versionId}.json`) &&
      FileUtils.exists(`${dir}/${versionId}.jar`);
  }

  /** 删除版本 */
  deleteVersion(versionId: string): boolean {
    const dir = `${FileUtils.getVersionsDir()}/${versionId}`;
    return FileUtils.delete(dir);
  }

  // ========== 工具方法 ==========

  private extractStringArray(data: Record<string, Object>, path: string): string[] {
    const parts = path.split('.');
    let current: Object = data;
    for (const part of parts) {
      current = (current as Record<string, Object>)[part];
      if (!current) {
        return [];
      }
    }
    if (Array.isArray(current)) {
      const items = current as Array<Object>;
      const result: string[] = [];
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (typeof item === 'string') {
          result.push(item);
        }
      }
      return result;
    }
    return [];
  }

  private parseLibraries(raw: Object | undefined): Library[] {
    if (!raw || !Array.isArray(raw)) {
      return [];
    }
    const result: Library[] = [];
    const arr = raw as Array<Record<string, Object>>;
    for (let i = 0; i < arr.length; i++) {
      const lib = arr[i];
      const entry: Library = {
        name: lib['name'] as string ?? '',
        downloads: lib['downloads'] as LibraryDownloads,
        natives: lib['natives'] as Record<string, string>,
        rules: lib['rules'] as LibraryRule[],
        url: lib['url'] as string
      };
      result.push(entry);
    }
    return result;
  }
}
