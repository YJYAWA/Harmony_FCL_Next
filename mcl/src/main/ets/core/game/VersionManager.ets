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
import { GameVersion, VersionType, Library, AssetIndex, AssetObject, JavaVersion,
  LibraryDownloads, LibraryRule, Artifact, VersionDownloads } from './GameTypes';
import { DownloadManager, DownloadTask, DownloadResult } from '../download/DownloadManager';
import { DownloadProvider, RemoteVersion } from '../download/DownloadProvider';
import { FileUtils } from '../util/FileUtils';
import { LibraryRules } from './LibraryRules';
import { VersionArguments } from './VersionArguments';
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

  /** 解析版本 JSON 中的 downloads 段 */
  private parseDownloads(raw: Object | undefined): VersionDownloads | undefined {
    if (!raw) {
      return undefined;
    }
    const obj = raw as Record<string, Object>;
    const downloads: VersionDownloads = {};
    const clientRaw = obj['client'];
    if (clientRaw) {
      downloads.client = VersionManager.parseArtifact(clientRaw as Record<string, Object>);
    }
    const serverRaw = obj['server'];
    if (serverRaw) {
      downloads.server = VersionManager.parseArtifact(serverRaw as Record<string, Object>);
    }
    return downloads;
  }

  private static parseArtifact(raw: Record<string, Object>): Artifact {
    return {
      path: raw['path'] as string ?? '',
      sha1: raw['sha1'] as string ?? '',
      size: raw['size'] as number ?? 0,
      url: raw['url'] as string ?? ''
    };
  }

  /**
   * 读取某个版本的原始 JSON 文本 (优先本地缓存)
   */
  private async fetchVersionJsonText(versionId: string): Promise<string | null> {
    const localPath = `${FileUtils.getVersionsDir()}/${versionId}/${versionId}.json`;
    const local = FileUtils.readText(localPath);
    if (local && local.length > 0) {
      return local;
    }

    const versions = await this.getRemoteVersions();
    const info = versions.find(v => v.version === versionId);
    if (!info) {
      return null;
    }
    try {
      const response = await httpGet(this.provider.injectURL(info.url));
      return await response.text();
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to fetch version json: ${versionId}, ${err}`);
      return null;
    }
  }

  /**
   * 解析单个版本 JSON 文本为 GameVersion
   */
  private parseVersionJson(text: string, fallbackId: string): GameVersion | null {
    try {
      const data = JSON.parse(text) as Record<string, Object>;
      const idVal = data['id'] as string;
      const typeVal = data['type'] as VersionType;
      const inheritsVal = data['inheritsFrom'] as string;
      const mainClassVal = data['mainClass'] as string;
      const releaseVal = data['releaseTime'] as string;
      const gv: GameVersion = {
        id: idVal ?? fallbackId,
        type: typeVal ?? VersionType.RELEASE,
        inheritsFrom: inheritsVal,
        mainClass: mainClassVal ?? '',
        downloads: this.parseDownloads(data['downloads']),
        arguments: VersionArguments.parse(data['arguments']),
        libraries: this.parseLibraries(data['libraries']),
        assetIndex: data['assetIndex'] as AssetIndex,
        javaVersion: data['javaVersion'] as JavaVersion,
        releaseTime: releaseVal ?? ''
      };
      return gv;
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to parse version json: ${fallbackId}, ${err}`);
      return null;
    }
  }

  /**
   * 沿 inheritsFrom 链解析出完整版本 (合并父版本的 libraries / arguments / assetIndex)
   *
   * 上游 FCL (FCLCore DefaultGameBuilder) 的行为：子版本只覆盖自己声明的字段，
   * 依赖库按 name 去重（子版本优先），arguments.jvm 拼接，assetIndex 继承父版本。
   */
  async resolveVersion(versionId: string): Promise<GameVersion | null> {
    const chain = await this.resolveVersionChain(versionId);
    if (chain.length === 0) {
      return null;
    }
    return this.mergeVersionChain(chain, versionId);
  }

  /**
   * 沿 inheritsFrom 链收集版本 JSON (子在前, 父在后)
   */
  async resolveVersionChain(versionId: string): Promise<GameVersion[]> {
    const chain: GameVersion[] = [];
    let currentId = versionId;
    const visited: Set<string> = new Set();

    while (currentId.length > 0 && !visited.has(currentId)) {
      visited.add(currentId);
      const text = await this.fetchVersionJsonText(currentId);
      if (!text) {
        break;
      }
      const parsed = this.parseVersionJson(text, currentId);
      if (!parsed) {
        break;
      }
      chain.push(parsed);
      currentId = parsed.inheritsFrom ?? '';
    }

    return chain;
  }

  /** 合并继承链 (父 → 子) */
  private mergeVersionChain(chain: GameVersion[], versionId: string): GameVersion {
    // chain[0] 为最上层子版本，chain[last] 为最底层父版本
    // 合并顺序：父 → 子
    let merged: GameVersion = {
      id: chain[0].id,
      type: chain[0].type,
      mainClass: chain[0].mainClass,
      arguments: { game: [], jvm: [] },
      libraries: [],
      assetIndex: undefined,
      javaVersion: undefined,
      releaseTime: chain[0].releaseTime,
      downloads: chain[0].downloads
    };

    for (let i = chain.length - 1; i >= 0; i--) {
      const v = chain[i];

      if (v.mainClass && v.mainClass.length > 0) {
        merged.mainClass = v.mainClass;
      }
      if (v.assetIndex) {
        merged.assetIndex = v.assetIndex;
      }
      if (v.javaVersion) {
        merged.javaVersion = v.javaVersion;
      }
      if (v.downloads && v.downloads.client) {
        // 客户端 JAR 归属于声明 downloads.client 的那个版本 (父版本)
        merged.downloads = v.downloads;
        merged.clientJarId = v.id;
      }

      // 依赖库：按 name 去重，子版本覆盖父版本
      for (const lib of v.libraries) {
        const idx = merged.libraries.findIndex(l => l.name === lib.name);
        if (idx >= 0) {
          merged.libraries[idx] = lib;
        } else {
          merged.libraries.push(lib);
        }
      }
      // arguments：父在前，子在后（同 key 由子覆盖）
      merged.arguments.game = VersionManager.mergeArgs(merged.arguments.game, v.arguments?.game ?? []);
      merged.arguments.jvm = VersionManager.mergeArgs(merged.arguments.jvm, v.arguments?.jvm ?? []);
    }

    // 依赖库二次去重: 同 groupId:artifactId 保留最高版本
    merged.libraries = LibraryRules.uniqueLibraries(merged.libraries);

    merged.id = versionId;
    return merged;
  }
  /** 合并两组启动参数：base 中同 key 被 override 覆盖，其余保留 */
  private static mergeArgs(base: string[], override: string[]): string[] {
    const result: string[] = [];
    const overridden: Set<string> = new Set();
    for (const arg of override) {
      const key = VersionManager.argKey(arg);
      if (key.length > 0) {
        overridden.add(key);
      }
    }
    for (const arg of base) {
      const key = VersionManager.argKey(arg);
      if (key.length === 0 || !overridden.has(key)) {
        result.push(arg);
      }
    }
    for (const arg of override) {
      result.push(arg);
    }
    return result;
  }

  /** 提取参数标识（"--foo" 或 "-Dfoo"）用于覆盖判定 */
  private static argKey(arg: string): string {
    if (arg.startsWith('--')) {
      const space = arg.indexOf(' ');
      return space > 0 ? arg.substring(0, space) : arg;
    }
    if (arg.startsWith('-D')) {
      const eq = arg.indexOf('=');
      return eq > 0 ? arg.substring(0, eq) : arg;
    }
    return '';
  }

  /** 获取远程版本的详细 JSON 信息 (含 inheritsFrom 继承链合并) */
  async getVersionDetail(versionId: string): Promise<GameVersion | null> {
    return this.resolveVersion(versionId);
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
      // 获取版本详情（含 inheritsFrom 继承链合并）
      const chain = await this.resolveVersionChain(versionId);
      if (chain.length === 0) {
        throw new Error(`Version ${versionId} not found`);
      }
      const version = this.mergeVersionChain(chain, versionId);

      // 创建目录
      const versionDir = `${FileUtils.getVersionsDir()}/${versionId}`;
      FileUtils.mkdirs(versionDir);

      // 保存整条继承链的原始 JSON（保留 inheritsFrom 等原始字段）
      // 加载器版本 (Forge/Fabric) 依赖父版本目录下的 json 才能被识别
      for (const v of chain) {
        const vDir = `${FileUtils.getVersionsDir()}/${v.id}`;
        FileUtils.mkdirs(vDir);
        const jsonPath = `${vDir}/${v.id}.json`;
        if (!FileUtils.exists(jsonPath)) {
          const raw = await this.fetchVersionJsonText(v.id);
          if (raw) {
            FileUtils.writeText(jsonPath, raw);
          }
        }
      }

      // 收集需要下载的文件
      const tasks: DownloadTask[] = [];

      // 1. 下载客户端 JAR —— 必须使用版本 JSON 中 downloads.client 提供的真实 URL
      //    （旧实现硬编码 launchermojang.com/v1/objects/<id>/client.jar，该 URL 不存在）
      //    继承型版本的 client.jar 归属于父版本目录
      const clientArtifact = version.downloads?.client;
      if (clientArtifact && clientArtifact.url.length > 0) {
        const ownerId = version.clientJarId ?? versionId;
        const ownerDir = `${FileUtils.getVersionsDir()}/${ownerId}`;
        FileUtils.mkdirs(ownerDir);
        tasks.push(new DownloadTask(
          this.provider.injectURL(clientArtifact.url),
          `${ownerDir}/${ownerId}.jar`,
          clientArtifact.sha1,
          clientArtifact.size,
          this.provider.buildHeaders(clientArtifact.sha1),
          this.provider.buildCandidates(clientArtifact.url)
        ));
      } else {
        throw new Error(`Version ${versionId} has no client download entry`);
      }

      // 2. 下载依赖库（按 rules 过滤平台不匹配的库）
      for (const lib of version.libraries) {
        if (!VersionManager.isLibraryAllowed(lib)) {
          continue;
        }

        const art = lib.downloads?.artifact;
        if (!art) {
          continue;
        }

        const libUrl = this.provider.injectURL(art.url);
        const libPath = `${FileUtils.getLibrariesDir()}/${art.path}`;

        tasks.push(new DownloadTask(libUrl, libPath, art.sha1, art.size,
          this.provider.buildHeaders(art.sha1), this.provider.buildCandidates(art.url)));
      }
      // 3. 下载资源索引
      if (version.assetIndex) {
        const assetUrl = this.provider.injectURL(version.assetIndex.url);
        const indexPath = `${FileUtils.getAssetsDir()}/indexes/${version.assetIndex.id}.json`;
        tasks.push(new DownloadTask(assetUrl, indexPath, version.assetIndex.sha1,
          version.assetIndex.size, this.provider.buildHeaders(version.assetIndex.sha1),
          this.provider.buildCandidates(version.assetIndex.url)));
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
      const originUrl = `${this.provider.getAssetBaseURL()}${prefix}/${obj.hash}`;
      tasks.push(new DownloadTask(assetUrl, assetPath, obj.hash, obj.size,
        this.provider.buildHeaders(obj.hash), this.provider.buildCandidates(originUrl)));
    }

    const downloader = new DownloadManager(this.provider.getConcurrency());
    downloader.addTasks(tasks);
    await downloader.startAll();
  }

  /** 获取已安装版本列表
   *
   * 兼容两类版本:
   * - 独立版本: 有 <id>.json + <id>.jar (客户端 jar)
   * - 加载器版本 (Forge/Fabric/NeoForge): 只有 <id>.json, 通过 inheritsFrom 继承客户端
   */
  getInstalledVersions(): string[] {
    const versionsDir = FileUtils.getVersionsDir();
    const dirs = FileUtils.listFiles(versionsDir);
    return dirs.filter(d => VersionManager.isVersionDirectoryInstalled(versionsDir, d));
  }

  /** 判断某个版本目录是否算"已安装" */
  private static isVersionDirectoryInstalled(versionsDir: string, versionId: string): boolean {
    const path = `${versionsDir}/${versionId}`;
    if (!FileUtils.isDirectory(path)) {
      return false;
    }
    // 至少要有版本描述文件
    if (!FileUtils.exists(`${path}/${versionId}.json`)) {
      return false;
    }
    // 有客户端 jar → 独立版本
    if (FileUtils.exists(`${path}/${versionId}.jar`)) {
      return true;
    }
    // 无 jar 但声明了 inheritsFrom → 加载器版本 (继承父版本的客户端)
    const raw = FileUtils.readJSON<Record<string, Object>>(`${path}/${versionId}.json`);
    if (!raw) {
      return false;
    }
    const inherits = raw['inheritsFrom'] as string;
    return inherits !== undefined && inherits.length > 0;
  }

  /** 检查版本是否已安装 */
  isVersionInstalled(versionId: string): boolean {
    return VersionManager.isVersionDirectoryInstalled(FileUtils.getVersionsDir(), versionId);
  }

  /** 获取版本的主类 (走继承链) */
  async getMainClass(versionId: string): Promise<string> {
    const version = await this.resolveVersion(versionId);
    if (!version || !version.mainClass || version.mainClass.length === 0) {
      return 'net.minecraft.client.main.Main';
    }
    return version.mainClass;
  }

  /** 删除版本 */
  deleteVersion(versionId: string): boolean {
    const dir = `${FileUtils.getVersionsDir()}/${versionId}`;
    return FileUtils.delete(dir);
  }

  /**
   * 重命名版本
   * 目录名与版本 JSON 文件名同步改名, JSON 内的 id 字段一并更新
   */
  renameVersion(oldId: string, newId: string): boolean {
    if (newId.trim().length === 0 || oldId === newId) {
      return false;
    }
    const versionsDir = FileUtils.getVersionsDir();
    const oldDir = `${versionsDir}/${oldId}`;
    const newDir = `${versionsDir}/${newId}`;
    if (!FileUtils.isDirectory(oldDir) || FileUtils.exists(newDir)) {
      return false;
    }

    // 1. 重命名 json 文件
    const oldJson = `${oldDir}/${oldId}.json`;
    const newJson = `${oldDir}/${newId}.json`;
    if (FileUtils.exists(oldJson)) {
      if (!FileUtils.rename(oldJson, newJson)) {
        return false;
      }
      // 更新 JSON 内的 id 字段
      const raw = FileUtils.readJSON<Record<string, Object>>(newJson);
      if (raw) {
        raw['id'] = newId;
        FileUtils.writeJSON(newJson, raw);
      }
    }

    // 2. 重命名 jar
    const oldJar = `${oldDir}/${oldId}.jar`;
    if (FileUtils.exists(oldJar)) {
      FileUtils.rename(oldJar, `${oldDir}/${newId}.jar`);
    }

    // 3. 重命名目录
    if (!FileUtils.rename(oldDir, newDir)) {
      return false;
    }
    return true;
  }

  /**
   * 复制版本 (生成可独立编辑的副本)
   * 复制整个版本目录 + 客户端 jar, 并把 JSON 的 id 改为新 id
   */
  duplicateVersion(oldId: string, newId: string): boolean {
    if (newId.trim().length === 0 || oldId === newId) {
      return false;
    }
    const versionsDir = FileUtils.getVersionsDir();
    const oldDir = `${versionsDir}/${oldId}`;
    const newDir = `${versionsDir}/${newId}`;
    if (!FileUtils.isDirectory(oldDir) || FileUtils.exists(newDir)) {
      return false;
    }

    if (!FileUtils.copyDir(oldDir, newDir)) {
      return false;
    }

    // 复制后的文件名仍是旧 id, 需要改名
    const copiedJson = `${newDir}/${oldId}.json`;
    if (FileUtils.exists(copiedJson)) {
      FileUtils.rename(copiedJson, `${newDir}/${newId}.json`);
    }
    const copiedJar = `${newDir}/${oldId}.jar`;
    if (FileUtils.exists(copiedJar)) {
      FileUtils.rename(copiedJar, `${newDir}/${newId}.jar`);
    }

    const finalJson = `${newDir}/${newId}.json`;
    const raw = FileUtils.readJSON<Record<string, Object>>(finalJson);
    if (raw) {
      raw['id'] = newId;
      FileUtils.writeJSON(finalJson, raw);
    }
    return true;
  }

  // ========== 工具方法 ==========

  /**
   * 判断库在 HarmonyOS NEXT 平台是否应被包含
   * 按 Mojang rules 语义顺序求值 (最后一条匹配规则决定结果)
   */
  static isLibraryAllowed(lib: Library): boolean {
    return LibraryRules.isAllowed(lib);
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
