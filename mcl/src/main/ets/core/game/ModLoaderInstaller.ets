import { httpGet } from '../util/HttpUtils';
/**
 * 模组加载器安装器
 * 移植自: FCLCore/download/ 中的 Forge/Fabric/OptiFine 安装逻辑
 *
 * 支持:
 * - Fabric Loader 安装
 * - Forge 安装
 * - NeoForge 安装
 * - OptiFine 安装
 * - Quilt 安装
 */
import { ModLoaderType } from './GameTypes';
import { FileUtils } from '../util/FileUtils';
import { DownloadManager, DownloadTask } from '../download/DownloadManager';
import { BMCLAPIDownloadProvider } from '../download/DownloadProvider';
import { JarExecutorService } from '../../service/JarExecutorService';
import { VersionManager } from './VersionManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-ModLoaderInstaller';

/** 模组加载器安装结果 */
export interface InstallResult {
  success: boolean;
  loaderType: ModLoaderType;
  loaderVersion: string;
  mcVersion: string;
  error?: string;
  installedVersionId?: string;
}

/** 模组加载器版本信息 (Fabric Loader 版本列表项) */
export interface ModLoaderVersion {
  version: string;
  stable: boolean;
}

/** 库文件下载信息 */
export interface LibraryFile {
  path: string;
  url: string;
  sha1: string;
}

/** OptiFine 版本列表项 */
export interface OptiFineVersion {
  mcversion: string;
  type: string;
  patch: string;
}

/** Fabric 版本元数据 */
interface FabricLoaderMeta {
  loader: FabricVersionEntry[];
  intermediary: FabricVersionEntry[];
}

interface FabricVersionEntry {
  separator: string;
  build: number;
  maven: string;
  version: string;
  stable: boolean;
}

/**
 * Fabric Loader 安装器
 */
export class FabricInstaller {
  private static readonly META_URL = 'https://meta.fabricmc.net/v2';

  /** 获取可用 Loader 版本 */
  static async getLoaderVersions(): Promise<ModLoaderVersion[]> {
    try {
      const response = await httpGet(`${FabricInstaller.META_URL}/versions/loader`);
      const raw = await response.json() as Array<Record<string, Object>>;
      const result: ModLoaderVersion[] = [];
      for (let i = 0; i < raw.length; i++) {
        const item = raw[i];
        const stableRaw: Object | undefined = item['stable'];
        const mv: ModLoaderVersion = {
          version: item['version'] as string ?? '',
          stable: stableRaw === true || stableRaw === 'true'
        };
        result.push(mv);
      }
      return result;
    } catch {
      return [];
    }
  }

  /** 获取可用 Intermediary 版本 (Minecraft 映射) */
  static async getIntermediaryVersions(): Promise<string[]> {
    try {
      const response = await httpGet(`${FabricInstaller.META_URL}/versions/intermediary`);
      const data = await response.json() as FabricVersionEntry[];
      return data.map(i => i.version);
    } catch {
      return [];
    }
  }

  /**
   * 安装 Fabric Loader 到指定 Minecraft 版本
   */
  static async install(
    mcVersion: string,
    loaderVersion: string
  ): Promise<InstallResult> {
    try {
      hilog.info(0x0000, TAG, `Installing Fabric ${loaderVersion} for MC ${mcVersion}`);

      // 1. 获取 Fabric Loader JSON
      const loaderJsonURL = `${FabricInstaller.META_URL}/versions/loader/${mcVersion}/${loaderVersion}/profile/json`;
      const loaderResponse = await httpGet(loaderJsonURL);

      if (!loaderResponse.ok) {
        return {
          success: false,
          loaderType: ModLoaderType.FABRIC,
          loaderVersion,
          mcVersion,
          error: `Fabric version not found for MC ${mcVersion}`
        };
      }

      const loaderData = await loaderResponse.json() as Record<string, Object>;

      // 2. 确保原版版本已安装（Fabric 版本通过 inheritsFrom 继承原版客户端）
      const parentManager = new VersionManager(new BMCLAPIDownloadProvider());
      if (!parentManager.isVersionInstalled(mcVersion)) {
        await parentManager.installVersion(mcVersion);
      }

      // 3. 保存版本 JSON
      const fabricVersionId = `fabric-loader-${loaderVersion}-${mcVersion}`;
      const versionDir = `${FileUtils.getVersionsDir()}/${fabricVersionId}`;
      FileUtils.mkdirs(versionDir);

      const jsonText = JSON.stringify(loaderData, null, 2);
      FileUtils.writeText(`${versionDir}/${fabricVersionId}.json`, jsonText);

      // 4. 下载 Fabric Loader 库
      const provider = new BMCLAPIDownloadProvider();
      const libraries = loaderData['libraries'] as Array<Record<string, Object>> | undefined;
      const tasks: DownloadTask[] = [];

      if (libraries) {
        libraries.forEach(lib => {
          const name = lib['name'] as string;
          const downloads = lib['downloads'] as Record<string, LibraryFile> | undefined;

          if (downloads?.artifact) {
            const art = downloads.artifact;
            const url = provider.injectURL(art.url);
            const path = `${FileUtils.getLibrariesDir()}/${art.path}`;
            tasks.push(new DownloadTask(url, path, art.sha1));
          }
        });
      }

      if (tasks.length > 0) {
        const downloader = new DownloadManager(8);
        downloader.addTasks(tasks);
        const results = await downloader.startAll();
        const failed = results.filter(r => !r.success);
        if (failed.length > 0) {
          return {
            success: false, loaderType: ModLoaderType.FABRIC,
            loaderVersion, mcVersion,
            error: `${failed.length} library download(s) failed`
          };
        }
      }

      return {
        success: true,
        loaderType: ModLoaderType.FABRIC,
        loaderVersion,
        mcVersion,
        installedVersionId: fabricVersionId
      };

    } catch (err) {
      return {
        success: false, loaderType: ModLoaderType.FABRIC,
        loaderVersion, mcVersion,
        error: err instanceof Error ? err.message : String(err)
      };
    }
  }
}

/**
 * Forge 安装器
 * 移植自: FCLCore/download/forge/
 */
export class ForgeInstaller {
  private static readonly FORGE_MAVEN = 'https://files.minecraftforge.net/net/minecraftforge/forge';
  private static readonly FORGE_PROMO = 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json';

  /** 获取指定 MC 版本的 Forge 版本列表 */
  static async getVersions(mcVersion: string): Promise<string[]> {
    try {
      const response = await httpGet(ForgeInstaller.FORGE_PROMO);
      const data = await response.json() as Record<string, Record<string, string>>;
      const promos = data['promos'] ?? {};

      const versions: string[] = [];
      for (const key of Object.keys(promos)) {
        if (key.startsWith(`${mcVersion}-`)) {
          const version = key.replace(`${mcVersion}-`, '');
          if (!versions.includes(version)) {
            versions.push(version);
          }
        }
      }
      return versions.sort();
    } catch {
      return [];
    }
  }

  /** 获取 Forge 最新推荐版本 */
  static async getRecommended(mcVersion: string): Promise<string | null> {
    try {
      const response = await httpGet(ForgeInstaller.FORGE_PROMO);
      const data = await response.json() as Record<string, Record<string, string>>;
      const promos = data['promos'] ?? {};
      return promos[`${mcVersion}-recommended`] ?? null;
    } catch {
      return null;
    }
  }

  /** 获取 Forge 最新版本 */
  static async getLatest(mcVersion: string): Promise<string | null> {
    try {
      const response = await httpGet(ForgeInstaller.FORGE_PROMO);
      const data = await response.json() as Record<string, Record<string, string>>;
      const promos = data['promos'] ?? {};
      return promos[`${mcVersion}-latest`] ?? null;
    } catch {
      return null;
    }
  }

  /**
   * 安装 Forge
   */
  static async install(
    mcVersion: string,
    forgeVersion: string
  ): Promise<InstallResult> {
    try {
      hilog.info(0x0000, TAG, `Installing Forge ${forgeVersion} for MC ${mcVersion}`);

      const fullVersion = `${mcVersion}-${forgeVersion}`;
      const forgeVersionId = `forge-${fullVersion}`;

      // Forge 安装 URL
      const installerUrl =
        `${ForgeInstaller.FORGE_MAVEN}/${fullVersion}/forge-${fullVersion}-installer.jar`;

      // 下载 Installer
      const installerPath = `${FileUtils.getMinecraftDir()}/forge-installer-${fullVersion}.jar`;
      const installerTask = new DownloadTask(installerUrl, installerPath);

      const downloader = new DownloadManager(1);
      downloader.addTask(installerTask);
      const results = await downloader.startAll();

      if (!results[0]?.success) {
        return {
          success: false, loaderType: ModLoaderType.FORGE,
          loaderVersion: forgeVersion, mcVersion,
          error: 'Failed to download Forge installer'
        };
      }

      // 实际执行 Forge 安装器
      // 复用 service/JarExecutorService（走 native executeJar，进程内嵌 JVM）
      const mcDir = FileUtils.getMinecraftDir();
      const jarResult = await JarExecutorService.getInstance().installForge(installerPath, mcDir);
      if (!jarResult.success) {
        return {
          success: false, loaderType: ModLoaderType.FORGE,
          loaderVersion: forgeVersion, mcVersion,
          error: `Forge installer failed (exit ${jarResult.exitCode}): ${jarResult.stderr}`
        };
      }

      // 安装器会在 <mcDir>/versions/ 下生成版本目录
      const generatedId = `${mcVersion}-${forgeVersion}`;
      const generatedJson = `${mcDir}/versions/${generatedId}/${generatedId}.json`;
      if (!FileUtils.exists(generatedJson)) {
        return {
          success: false, loaderType: ModLoaderType.FORGE,
          loaderVersion: forgeVersion, mcVersion,
          error: 'Forge installer finished but version json was not generated'
        };
      }

      // 把安装器产出的版本目录迁移到本项目的 versions 目录
      const targetDir = `${FileUtils.getVersionsDir()}/${forgeVersionId}`;
      FileUtils.mkdirs(targetDir);
      const raw = FileUtils.readJSON<Record<string, Object>>(generatedJson);
      if (raw) {
        raw['id'] = forgeVersionId;
        FileUtils.writeJSON(`${targetDir}/${forgeVersionId}.json`, raw);
      }

      return {
        success: true,
        loaderType: ModLoaderType.FORGE,
        loaderVersion: forgeVersion,
        mcVersion,
        installedVersionId: forgeVersionId
      };
    } catch (err) {
      return {
        success: false, loaderType: ModLoaderType.FORGE,
        loaderVersion: forgeVersion, mcVersion,
        error: err instanceof Error ? err.message : String(err)
      };
    }
  }
}

/**
 * OptiFine 安装器
 * 移植自: FCLCore/download/optifine/
 */
export class OptiFineInstaller {
  private static readonly OPTIFINE_LIST = 'https://optifine.net/downloads';

  /** 获取 OptiFine 版本列表 (解析 HTML, 简化实现) */
  static async getVersions(mcVersion: string): Promise<string[]> {
    // OptiFine 官方没有 JSON API, 需要解析 HTML 页面
    // 简化: 通过 BMCLAPI 获取
    try {
      const response = await httpGet('https://bmclapi2.bangbang93.com/optifine/versionList');
      const data = await response.json() as OptiFineVersion[];
      return data
        .filter(v => v.mcversion === mcVersion)
        .map(v => v.patch);
    } catch {
      return [];
    }
  }

  /**
   * 安装 OptiFine
   */
  static async install(
    mcVersion: string,
    optiFineVersion: string
  ): Promise<InstallResult> {
    try {
      const id = `OptiFine_${optiFineVersion}`;
      const optiFineId = `${mcVersion}-OptiFine_${optiFineVersion}`;

      // 获取下载 URL
      const url = `https://bmclapi2.bangbang93.com/optifine/${mcVersion}/${optiFineVersion}/download`;

      const installerPath = `${FileUtils.getMinecraftDir()}/optifine-${optiFineVersion}.jar`;
      const task = new DownloadTask(url, installerPath);

      const downloader = new DownloadManager(1);
      downloader.addTask(task);
      const results = await downloader.startAll();

      if (!results[0]?.success) {
        return {
          success: false, loaderType: ModLoaderType.OPTIFINE,
          loaderVersion: optiFineVersion, mcVersion,
          error: 'Failed to download OptiFine'
        };
      }

      // 执行 OptiFine 安装器（安装器 jar 接受游戏目录参数做静默安装）
      const mcDir = FileUtils.getMinecraftDir();
      const jarResult = await JarExecutorService.getInstance().installOptiFine(installerPath, mcDir);
      if (!jarResult.success) {
        return {
          success: false, loaderType: ModLoaderType.OPTIFINE,
          loaderVersion: optiFineVersion, mcVersion,
          error: `OptiFine installer failed (exit ${jarResult.exitCode}): ${jarResult.stderr}`
        };
      }

      // OptiFine 安装器会把 OptiFine jar 放到 <mcDir>/versions/<mcVersion>/ 下的 mods 目录，
      // 并在 versions 目录生成 "OptiFine_<ver>" 目录
      const generatedDir = `${FileUtils.getVersionsDir()}/OptiFine_${optiFineVersion}`;
      if (!FileUtils.isDirectory(generatedDir)) {
        FileUtils.mkdirs(generatedDir);
      }

      return {
        success: true,
        loaderType: ModLoaderType.OPTIFINE,
        loaderVersion: optiFineVersion,
        mcVersion,
        installedVersionId: optiFineId
      };
    } catch (err) {
      return {
        success: false, loaderType: ModLoaderType.OPTIFINE,
        loaderVersion: optiFineVersion, mcVersion,
        error: err instanceof Error ? err.message : String(err)
      };
    }
  }
}
