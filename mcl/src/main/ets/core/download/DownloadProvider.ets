import { httpGet } from '../util/HttpUtils';
/**
 * 下载提供者接口
 * 移植自: FCLCore/src/main/java/com/tungsten/fclcore/download/DownloadProvider.java
 *
 * 对齐上游 FCL 1.3.4.x：
 * - BMCLAPI 支持多镜像节点（慢速节点自动切换）
 * - 下载请求带 x-bmclapi-hash 头做 SHA-1 校验
 */
import { BMCLAPI_NODES, getCachedMirrors, MOJANG_BASE } from './SourceProber';

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
   * 构建下载候选地址列表（按优先级）
   * 第一个为当前使用的源，其余为回退节点
   */
  buildCandidates(baseURL: string): string[];

  /**
   * 构建下载请求头
   * @param sha1 期望的文件 SHA-1（BMCLAPI 用 x-bmclapi-hash 做服务端校验）
   */
  buildHeaders(sha1?: string): Record<string, string>;

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
    this.versionListUrl = MOJANG_BASE;
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

  buildCandidates(baseURL: string): string[] {
    return [baseURL];
  }

  buildHeaders(sha1?: string): Record<string, string> {
    if (sha1 !== undefined && sha1.length > 0) {
      return { 'x-bmclapi-hash': sha1 };
    }
    return {};
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

  constructor(baseUrl?: string) {
    this.baseUrl = baseUrl ?? getCachedMirrors()[0] ?? BMCLAPI_NODES[0];
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

  /**
   * 构建候选地址：当前节点优先，其余镜像节点与官方源作为回退
   * 对齐 PCL2 的 DlSourceOrder：只重排，不删源
   */
  buildCandidates(baseURL: string): string[] {
    const result: string[] = [];
    const push = (url: string): void => {
      if (url.length > 0 && !result.includes(url)) {
        result.push(url);
      }
    };
    push(this.injectURL(baseURL));
    for (const node of getCachedMirrors()) {
      push(node + this.mirrorSuffix(baseURL));
    }
    push(baseURL);
    return result;
  }

  /** 计算官方 URL 相对镜像根的路径后缀 */
  private mirrorSuffix(baseURL: string): string {
    const mappings: Array<[string, string]> = [
      ['https://launchermeta.mojang.com', ''],
      ['https://launcher.mojang.com', ''],
      ['https://libraries.minecraft.net', '/libraries'],
      ['https://resources.download.minecraft.net', '/assets'],
      ['https://files.minecraftforge.net', '/forge'],
      ['https://meta.fabricmc.net', '/fabric-meta']
    ];
    for (const mapping of mappings) {
      if (baseURL.startsWith(mapping[0])) {
        return baseURL.substring(mapping[0].length);
      }
    }
    return baseURL;
  }

  buildHeaders(sha1?: string): Record<string, string> {
    if (sha1 !== undefined && sha1.length > 0) {
      return { 'x-bmclapi-hash': sha1 };
    }
    return {};
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
  private provider: DownloadProvider;

  constructor(provider: DownloadProvider) {
    this.provider = provider;
  }

  async getVersions(): Promise<RemoteVersion[]> {
    const url = this.provider.getVersionListURL();
    const response = await httpGet(url);
    const data = await response.json() as Record<string, Object>;

    const versions = data['versions'] as Array<Record<string, string>>;
    if (!versions) {
      return [];
    }

    const result: RemoteVersion[] = [];
    for (let i = 0; i < versions.length; i++) {
      const v = versions[i];
      const rv: RemoteVersion = {
        version: v['id'] ?? '',
        type: (v['type'] ?? 'release') as VersionType,
        releaseTime: v['releaseTime'] ?? '',
        url: v['url'] ?? ''
      };
      result.push(rv);
    }
    return result;
  }

  async getVersion(version: string): Promise<RemoteVersion | null> {
    const versions = await this.getVersions();
    return versions.find(v => v.version === version) ?? null;
  }
}
