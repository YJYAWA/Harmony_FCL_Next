import { httpGet, httpPost } from '../util/HttpUtils';
/**
 * 下载提供者接口
 * 移植自: FCLCore/src/main/java/com/tungsten/fclcore/download/DownloadProvider.java
 */
import { http } from '@kit.NetworkKit';

/** 下载源接口定义 */
export interface DownloadProvider {
  /** 获取版本列表 URL */
  getVersionListURL(): string;

  /** 获取资源基础 URL */
  getAssetBaseURL(): string;

  /**
   * URL 注入 - 将官方 URL 转换为镜像 URL
   * @param baseURL 原始 Mojang/Forge 提供 URL
   * @returns 等价的镜像 URL
   */
  injectURL(baseURL: string): string;

  /**
   * 根据 ID 获取版本列表
   * @param id 版本列表类型: "game", "fabric", "forge" 等
   */
  getVersionListById(id: string): VersionList;

  /** 最大并发下载数 */
  getConcurrency(): number;
}

/** 版本列表接口 */
export interface VersionList {
  getVersions(): Promise<RemoteVersion[]>;
  getVersion(version: string): Promise<RemoteVersion | null>;
}

/** 远程版本信息 */
export interface RemoteVersion {
  /** 版本 ID */
  version: string;
  /** 版本类型: release, snapshot, old_beta, old_alpha */
  type: VersionType;
  /** 发布日期 */
  releaseTime: string;
  /** JSON 元数据 URL */
  url: string;
}

/** 版本类型 */
export enum VersionType {
  RELEASE = 'release',
  SNAPSHOT = 'snapshot',
  OLD_BETA = 'old_beta',
  OLD_ALPHA = 'old_alpha'
}

/** 默认下载提供者 - 使用 Mojang 官方源 */
export class MojangDownloadProvider implements DownloadProvider {
  private readonly versionListUrl: string;
  private readonly assetBaseUrl: string;

  constructor() {
    this.versionListUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest.json';
    this.assetBaseUrl = 'https://resources.download.minecraft.net/';
  }

  getVersionListURL(): string {
    return this.versionListUrl;
  }

  getAssetBaseURL(): string {
    return this.assetBaseUrl;
  }

  injectURL(baseURL: string): string {
    // 官方源不需要注入，直接返回原始 URL
    return baseURL;
  }

  getVersionListById(id: string): VersionList {
    return new GameVersionList(this);
  }

  getConcurrency(): number {
    return 8;
  }
}

/** BMCLAPI 镜像下载提供者 */
export class BMCLAPIDownloadProvider implements DownloadProvider {
  private readonly baseUrl: string;
  private readonly versionListUrl: string;
  private readonly assetBaseUrl: string;

  constructor() {
    this.baseUrl = 'https://bmclapi2.bangbang93.com';
    this.versionListUrl = this.baseUrl + '/mc/game/version_manifest.json';
    this.assetBaseUrl = this.baseUrl + '/assets/';
  }

  getVersionListURL(): string {
    return this.versionListUrl;
  }

  getAssetBaseURL(): string {
    return this.assetBaseUrl;
  }

  injectURL(baseURL: string): string {
    // 将官方 URL 替换为 BMCLAPI 镜像
    let url = baseURL;

    // 替换常见域名
    url = url.replace('https://launchermeta.mojang.com', this.baseUrl);
    url = url.replace('https://launcher.mojang.com', this.baseUrl);
    url = url.replace('https://libraries.minecraft.net', `${this.baseUrl}/libraries`);
    url = url.replace('https://resources.download.minecraft.net', `${this.baseUrl}/assets`);
    url = url.replace('https://files.minecraftforge.net', `${this.baseUrl}/forge`);
    url = url.replace('https://meta.fabricmc.net', `${this.baseUrl}/fabric-meta`);

    return url;
  }

  getVersionListById(id: string): VersionList {
    return new GameVersionList(this);
  }

  getConcurrency(): number {
    return 16;
  }
}

/** Minecraft 游戏版本列表 */
class GameVersionList implements VersionList {
  constructor(private provider: DownloadProvider) {
  }

  async getVersions(): Promise<RemoteVersion[]> {
    const url = this.provider.getVersionListURL();
    const response = await httpGet(url);
    const data = await response.json() as Record<string, Object>;

    const versions = data['versions'] as Array<Record<string, string>>;
    if (!versions) {
      return [];
    }

    return versions.map(v => ({
      version: v['id'] ?? '',
      type: (v['type'] ?? 'release') as VersionType,
      releaseTime: v['releaseTime'] ?? '',
      url: v['url'] ?? ''
    }));
  }

  async getVersion(version: string): Promise<RemoteVersion | null> {
    const versions = await this.getVersions();
    return versions.find(v => v.version === version) ?? null;
  }
}
