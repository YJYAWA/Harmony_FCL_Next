/**
 * 整合包安装器
 *
 * 移植自上游 FCL（FCL-Team/FoldCraftLauncher）：
 *   - ModpackHelper.readModpackManifest  → detectModpackType + parseModpackManifest
 *   - ModpackInstallTask                 → 解压 zip 到游戏实例目录
 *   - MinecraftInstanceTask               → 写整合包配置（fcl_modpack.json）
 *   - McbbsModpackLocalInstallTask        → MCBBS 专用安装流程（addons → 版本 + libraries）
 *   - HMCLModpackInstallTask             → HMCL 专用安装流程（minecraft/pack.json → 版本）
 *   - CurseModpackProvider / ModrinthModpackProvider → 文件下载列表
 *
 * 与 FCL 的关键差异：
 *   1. FCL 是 Android/Kotlin，跑在 JVM 里，能直接用 commons-compress 的 ZipFile；
 *      本项目是 ArkTS，改为「zlib.decompressFile 解压整个 zip → 在目录里操作」。
 *   2. FCL 的 Profile / Repository / Task 调度框架在 Next 侧不存在，
 *      改为直接调用本项目的 VersionManager + DownloadManager + FileUtils。
 *   3. FCL 的 CurseForge 下载需要 CurseForge API Key；本项目用 manifest 内的
 *      fileName 拼 edge.forgecdn.net 直链（无 Key 也能下，与 FCL 的 fallback 一致）。
 */
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileUtils } from '../util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { VersionManager, InstallCallbacks } from '../game/VersionManager';
import { ForgeInstaller, FabricInstaller } from '../game/ModLoaderInstaller';
import { DownloadManager, DownloadTask } from '../download/DownloadManager';
import { BMCLAPIDownloadProvider } from '../download/DownloadProvider';
import {
  ModpackManifest, ModpackType, ModpackFileEntry,
  detectModpackType, parseModpackManifest
} from './ModpackManifest';

const TAG = 'FCL-ModpackInstaller';

/** 安装结果 */
export interface ModpackInstallResult {
  success: boolean;
  /** 安装后的版本 id */
  versionId: string;
  /** 整合包名称 */
  name: string;
  /** 失败原因 */
  error?: string;
}

/** 安装阶段 */
export type ModpackStage = 'reading' | 'extracting' | 'downloading' | 'installing' | 'complete' | 'error';

/** 整合包安装进度 */
export interface ModpackProgress {
  stage: ModpackStage;
  message: string;
  /** 0-1 */
  progress: number;
}

/** 进度回调函数类型 */
export type ModpackProgressCallback = (progress: ModpackProgress) => void;

export class ModpackInstaller {
  private static readonly ZIP_TIMEOUT_MS: number = 300000;
  /** 整合包配置文件名（放在 versions/<id>/ 下，标记该版本是整合包） */
  private static readonly CONFIG_FILE: string = 'fcl_modpack.json';

  /**
   * 从本地 zip 安装整合包
   *
   * @param zipPath 本地 zip 文件路径（沙箱内真实路径，非 uri）
   * @param name    实例名（版本 id）
   * @param ctx     UIAbilityContext（用于 tempDir / picker）
   */
  static async installFromZip(
    ctx: common.UIAbilityContext,
    zipPath: string,
    name: string,
    onProgress?: ModpackProgressCallback
  ): Promise<ModpackInstallResult> {
    const report = (stage: ModpackStage, message: string, progress: number): void => {
      onProgress?.({ stage: stage, message: message, progress: progress });
    };

    try {
      if (!FileUtils.exists(zipPath)) {
        return { success: false, versionId: '', name: name, error: '整合包文件不存在' };
      }

      // ── 1. 解压到临时目录 ──
      report('extracting', '正在解压整合包...', 0.05);
      const stamp = Date.now().toString();
      const extractDir = `${ctx.tempDir}/fcl_modpack_${stamp}`;
      FileUtils.mkdirs(extractDir);
      try {
        await ModpackInstaller.decompress(zipPath, extractDir);
      } catch (err) {
        FileUtils.delete(extractDir);
        return { success: false, versionId: '', name: name, error: `解压失败: ${(err as BusinessError).message}` };
      }

      try {
        // ── 2. 检测并解析 manifest ──
        report('reading', '正在读取整合包信息...', 0.2);
        const type = detectModpackType(extractDir);
        const manifest = parseModpackManifest(extractDir, type);
        if (!manifest) {
          return { success: false, versionId: '', name: name, error: '无法识别的整合包格式' };
        }
        hilog.info(0x0000, TAG, `modpack type=${type} name=${manifest.name} mc=${manifest.gameVersion}`);

        const versionId = ModpackInstaller.sanitizeVersionId(name);
        const mcDir = FileUtils.getMinecraftDir();
        // 版本目录（共享）：<gameDir>/versions/<id>/
        const versionDir = `${mcDir}/versions/${versionId}`;
        // 实例目录（隔离）：<gameDir>/instances/<id>/，放 mods/config/saves
        const instanceDir = `${mcDir}/instances/${versionId}`;

        // ── 3. 检查重名 ──
        if (FileUtils.exists(`${versionDir}/${versionId}.json`) &&
          !FileUtils.exists(`${versionDir}/${ModpackInstaller.CONFIG_FILE}`)) {
          return {
            success: false, versionId: '', name: name,
            error: `版本 ${versionId} 已存在（非整合包），请换个名字`
          };
        }

        // ── 4. 安装原版 Minecraft + 模组加载器 ──
        const baseVersion = ModpackInstaller.resolveGameVersion(manifest);
        if (baseVersion.length === 0) {
          return { success: false, versionId: '', name: name, error: '整合包未声明 Minecraft 版本' };
        }

        report('installing', `正在安装 Minecraft ${baseVersion}...`, 0.25);
        const vm = new VersionManager(new BMCLAPIDownloadProvider());
        const installCallbacks: InstallCallbacks = {
          onProgress: (p) => {
            // InstallProgress 没有百分比字段，用已完成文件数估算
            const ratio = p.totalFiles > 0 ? p.completedFiles / p.totalFiles : 0;
            report('installing', p.currentFile, 0.25 + ratio * 0.35);
          }
        };
        try {
          await vm.installVersion(baseVersion, installCallbacks);
        } catch (err) {
          return {
            success: false, versionId: '', name: name,
            error: `安装 Minecraft ${baseVersion} 失败: ${(err as BusinessError).message}`
          };
        }

        // 4b. 安装模组加载器（Forge/Fabric），失败不阻断（原版仍可启动）
        let loaderVersionId = baseVersion;
        try {
          report('installing', `正在安装 ${manifest.modLoader}...`, 0.6);
          loaderVersionId = await ModpackInstaller.installModLoader(manifest, baseVersion);
        } catch (err) {
          hilog.warn(0x0000, TAG, `mod loader install failed (continue with vanilla): ${err}`);
        }

        // ── 5. 建立整合包实例目录 ──
        report('installing', '正在创建整合包实例...', 0.62);
        // 实例目录：整合包之间互相隔离（对齐 FCL 的 isolateGameDir）
        // 版本 JSON 与 libraries 仍在共享的 gameDir/versions，只有 mods/config/saves 等隔离
        FileUtils.mkdirs(instanceDir);
        const created = ModpackInstaller.createInstance(versionId, loaderVersionId);
        if (!created) {
          return { success: false, versionId: '', name: name, error: '创建整合包实例失败' };
        }

        // ── 6. 解压 overrides 到实例目录 ──
        report('extracting', '正在写入整合包文件...', 0.68);
        ModpackInstaller.applyOverrides(extractDir, manifest, instanceDir);

        // ── 7. 下载需要联网获取的模组 ──
        const downloadEntries = ModpackInstaller.collectDownloadFiles(manifest);
        if (downloadEntries.length > 0) {
          report('downloading', `正在下载 ${downloadEntries.length} 个模组...`, 0.7);
          const ok = await ModpackInstaller.downloadFiles(downloadEntries, instanceDir,
            (ratio: number) => {
              report('downloading', `正在下载模组 (${Math.round(ratio * 100)}%)`, 0.7 + ratio * 0.25);
            });
          if (!ok) {
            return { success: false, versionId: '', name: name, error: '模组下载失败' };
          }
        }

        // ── 8. 写整合包配置 ──
        report('installing', '正在写入整合包配置...', 0.96);
        ModpackInstaller.writeConfig(versionDir, instanceDir, manifest, loaderVersionId, type);

        report('complete', '整合包安装完成', 1.0);
        hilog.info(0x0000, TAG, `modpack installed: ${versionId} (${manifest.type})`);
        return {
          success: true,
          versionId: versionId,
          name: manifest.name
        };
      } finally {
        FileUtils.delete(extractDir);
      }
    } catch (err) {
      const error = (err as BusinessError).message;
      hilog.error(0x0000, TAG, `installFromZip failed: ${error}`);
      return { success: false, versionId: '', name: name, error: error };
    }
  }

  /**
   * 解析整合包实际使用的 Minecraft 版本 + 需要安装的模组加载器。
   *
   * 对齐 FCL 的 GameBuilder.version(addon.getId(), addon.getVersion())：
   * 整合包的 addons 同时声明 minecraft 与 forge/fabric，
   * 此时要装的是「原版 + 加载器」，而不是直接下载一个叫 forge-x.y.z 的版本
   * （Mojang 清单里没有这种 id，直接 installVersion 必然失败）。
   */
  private static resolveGameVersion(manifest: ModpackManifest): string {
    return manifest.gameVersion;
  }

  /**
   * 安装整合包所需的模组加载器（Forge / Fabric / OptiFine）
   * @returns 安装后的版本 id；无需加载器时返回原版版本 id
   */
  private static async installModLoader(manifest: ModpackManifest,
    baseVersion: string): Promise<string> {
    if (manifest.modLoader.length === 0 || manifest.modLoaderVersion.length === 0) {
      return baseVersion;
    }
    hilog.info(0x0000, TAG,
      `installing mod loader ${manifest.modLoader} ${manifest.modLoaderVersion} for ${baseVersion}`);

    if (manifest.modLoader === 'forge') {
      const result = await ForgeInstaller.install(baseVersion, manifest.modLoaderVersion);
      if (!result.success) {
        throw new Error(`Forge 安装失败: ${result.error ?? '未知错误'}`);
      }
      return result.installedVersionId ?? baseVersion;
    }
    if (manifest.modLoader === 'fabric') {
      const result = await FabricInstaller.install(baseVersion, manifest.modLoaderVersion);
      if (!result.success) {
        throw new Error(`Fabric 安装失败: ${result.error ?? '未知错误'}`);
      }
      return result.installedVersionId ?? baseVersion;
    }
    if (manifest.modLoader === 'quilt') {
      // Quilt 走 Fabric 兼容路径（FabricInstaller 内部按 fabric 元数据拉取）
      const result = await FabricInstaller.install(baseVersion, manifest.modLoaderVersion);
      if (!result.success) {
        throw new Error(`Quilt 安装失败: ${result.error ?? '未知错误'}`);
      }
      return result.installedVersionId ?? baseVersion;
    }
    return baseVersion;
  }

  /**
   * 创建整合包实例的版本目录。
   *
   * 版本 JSON 放在共享的 <gameDir>/versions/<id>/ 下（这样版本列表能识别它、
   * classpath 能找到 client.jar），而 mods/config/saves 放在独立实例目录。
   */
  private static createInstance(versionId: string, gameVersion: string): boolean {
    const mcDir = FileUtils.getMinecraftDir();
    const versionsDir = `${mcDir}/versions`;
    const versionDir = `${versionsDir}/${versionId}`;
    FileUtils.mkdirs(versionDir);

    // 找基线版本 JSON：优先整合包声明的原版，其次任意已装版本
    const baselineId = ModpackInstaller.findBaselineVersion(versionsDir, gameVersion);
    if (baselineId.length > 0) {
      const src = `${versionsDir}/${baselineId}/${baselineId}.json`;
      if (FileUtils.exists(src)) {
        FileUtils.copy(src, `${versionDir}/${versionId}.json`);
        // 修正 JSON 内的 id
        const text = FileUtils.readText(`${versionDir}/${versionId}.json`);
        if (text) {
          try {
            const obj = JSON.parse(text) as Record<string, Object>;
            obj['id'] = versionId;
            FileUtils.writeJSON(`${versionDir}/${versionId}.json`, obj);
          } catch (err) {
            // JSON 解析失败就保留原样
          }
        }
      }
    }
    return true;
  }

  /** 找可作为基线的已安装版本 */
  private static findBaselineVersion(versionsDir: string, preferred: string): string {
    if (preferred.length > 0 && FileUtils.exists(`${versionsDir}/${preferred}/${preferred}.json`)) {
      return preferred;
    }
    // 退而求其次：找任意一个 release 版本
    try {
      const names = fs.listFileSync(versionsDir);
      for (const name of names) {
        if (FileUtils.exists(`${versionsDir}/${name}/${name}.json`)) {
          return name;
        }
      }
    } catch (err) {
      return '';
    }
    return '';
  }

  /**
   * 把整合包内的 overrides / minecraft 目录内容写入目标。
   *
   * 对应 FCL ModpackInstallTask 的「把 zip 内指定目录解压到 run 目录」。
   * 写入位置分两类：
   *   - 实例目录：mods、config、shaderpacks、resourcepacks、saves、options.txt 等
   *   - 共享 gameDir：versions（整合包自带的版本）、libraries 等跨实例共享的资源
   */
  private static applyOverrides(extractDir: string, manifest: ModpackManifest,
    instanceDir: string): void {
    let sourceDir = '';
    if (manifest.overridesDir.length > 0) {
      const candidate = `${extractDir}/${manifest.overridesDir}`;
      if (FileUtils.isDirectory(candidate)) {
        sourceDir = candidate;
      }
    }
    if (sourceDir.length === 0) {
      // 手工整合包：找 .minecraft 或顶层 versions
      const manualMc = `${extractDir}/.minecraft`;
      if (FileUtils.isDirectory(manualMc)) {
        sourceDir = manualMc;
      } else if (FileUtils.isDirectory(`${extractDir}/versions`)) {
        sourceDir = extractDir;
      }
    }
    if (sourceDir.length === 0) {
      return;
    }
    const mcDir = FileUtils.getMinecraftDir();
    ModpackInstaller.copyTreeSplit(sourceDir, instanceDir, mcDir);
  }

  /**
   * 递归复制目录，按顶层目录名分流：
   *   - versions / libraries → 共享 gameDir（跨实例共享，避免重复占用空间）
   *   - 其它（mods / config / saves / ...）→ 实例目录
   */
  private static copyTreeSplit(srcDir: string, instanceDir: string, sharedDir: string): void {
    FileUtils.mkdirs(instanceDir);
    let names: string[] = [];
    try {
      names = fs.listFileSync(srcDir);
    } catch (err) {
      return;
    }
    for (const name of names) {
      const src = `${srcDir}/${name}`;
      // versions / libraries 属于跨实例共享资源，放共享 gameDir
      const isShared = name === 'versions' || name === 'libraries';
      const destRoot = isShared ? sharedDir : instanceDir;
      const dest = `${destRoot}/${name}`;
      try {
        if (FileUtils.isDirectory(src)) {
          ModpackInstaller.copyTreeSplit(src, destRoot, sharedDir);
        } else {
          FileUtils.mkdirs(destRoot);
          FileUtils.copy(src, dest);
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, `copy failed: ${src} -> ${dest}`);
      }
    }
  }

  /** 收集需要联网下载的文件（zip 内已有的不进列表） */
  private static collectDownloadFiles(manifest: ModpackManifest): ModpackFileEntry[] {
    const result: ModpackFileEntry[] = [];
    for (const file of manifest.files) {
      if (file.extractedPath !== undefined && file.extractedPath.length > 0) {
        continue;
      }
      if (file.url.length === 0) {
        continue;
      }
      result.push(file);
    }
    return result;
  }

  /**
   * 下载模组文件到游戏目录。
   * @param onProgress 0-1
   */
  private static async downloadFiles(
    files: ModpackFileEntry[],
    mcDir: string,
    onProgress: (progress: number) => void
  ): Promise<boolean> {
    const manager = new DownloadManager(4);
    for (const file of files) {
      const target = `${mcDir}/${file.path}`;
      FileUtils.mkdirs(target.substring(0, target.lastIndexOf('/')));
      const task = new DownloadTask(file.url, target, file.sha1, file.size);
      manager.addTask(task);
    }
    const results = await manager.startAll();
    let ok = true;
    for (const result of results) {
      if (!result.success) {
        ok = false;
        hilog.error(0x0000, TAG, `download failed: ${result.error ?? ''}`);
      }
    }
    onProgress(1.0);
    return ok;
  }

  /**
   * 写整合包配置。
   *
   * 配置放在版本目录（<gameDir>/versions/<id>/fcl_modpack.json），这样版本列表能识别
   * 哪些版本是整合包；instanceDir 字段记录该整合包的独立实例目录。
   *
   * 对应 FCL 的 ModpackConfiguration（记录类型/版本，供后续更新与识别使用）。
   */
  private static writeConfig(
    versionDir: string,
    instanceDir: string,
    manifest: ModpackManifest,
    gameVersion: string,
    type: ModpackType
  ): void {
    const config: ModpackConfig = {
      type: type,
      name: manifest.name,
      version: manifest.version,
      author: manifest.author,
      description: manifest.description,
      gameVersion: gameVersion,
      modLoader: manifest.modLoader,
      modLoaderVersion: manifest.modLoaderVersion,
      instanceDir: instanceDir,
      installedAt: Date.now(),
      minMemory: manifest.minMemory,
      launchArguments: manifest.launchArguments,
      javaArguments: manifest.javaArguments
    };
    FileUtils.writeJSON(`${versionDir}/${ModpackInstaller.CONFIG_FILE}`, config);
  }

  /**
   * 读取整合包配置（版本列表页据此标识整合包）
   * @param versionDir <gameDir>/versions/<id>
   */
  static readConfig(versionDir: string): ModpackConfig | null {
    return FileUtils.readJSON<ModpackConfig>(`${versionDir}/${ModpackInstaller.CONFIG_FILE}`);
  }

  /** 把实例名转成合法的版本 id */
  private static sanitizeVersionId(name: string): string {
    let id = name.trim().replace(/[\/\s\\:*?"<>|]/g, '_');
    if (id.length === 0) {
      id = 'modpack';
    }
    return id;
  }

  /** Promise 化 zlib.decompressFile */
  private static decompress(zipPath: string, destDir: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error('解压超时'));
      }, ModpackInstaller.ZIP_TIMEOUT_MS);
      try {
        zlib.decompressFile(zipPath, destDir, (err: BusinessError) => {
          clearTimeout(timer);
          if (err && err.code) {
            reject(new Error(err.message));
          } else {
            resolve();
          }
        });
      } catch (err) {
        clearTimeout(timer);
        reject(err as Error);
      }
    });
  }
}

/** 整合包配置（对应 FCL 的 ModpackConfiguration） */
export interface ModpackConfig {
  type: ModpackType;
  name: string;
  version: string;
  author: string;
  description: string;
  gameVersion: string;
  modLoader: string;
  modLoaderVersion: string;
  /** 该整合包的独立实例目录（mods/config/saves 所在） */
  instanceDir: string;
  installedAt: number;
  minMemory: number;
  launchArguments: string[];
  javaArguments: string[];
}
