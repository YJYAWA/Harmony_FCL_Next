/**
 * 模组/资源包/光影/存档管理器
 * 移植自: FCLCore 的 mod 管理 + FCL UI 中的管理功能
 */
import { FileUtils } from '../util/FileUtils';
import { Constants } from '../util/Constants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-ModManager';

/** 管理项类型 */
export enum ManagedItemType {
  MOD = 'mod',
  RESOURCE_PACK = 'resourcepack',
  SHADER_PACK = 'shaderpack',
  SAVE = 'save',
  DATA_PACK = 'datapack'
}

/** 管理项的通用信息 */
export interface ManagedItem {
  /** 文件/目录名 */
  name: string;
  /** 完整路径 */
  path: string;
  /** 文件大小 */
  size: number;
  /** 最后修改时间 */
  lastModified: number;
  /** 是否为目录 */
  isDirectory: boolean;
  /** 是否已启用 */
  enabled: boolean;
  /** 类型 */
  type: ManagedItemType;
  /** 额外元数据 */
  metadata?: Record<string, string>;
}

/** 模组信息 */
export interface ModInfo extends ManagedItem {
  type: ManagedItemType.MOD;
  modId?: string;
  modName?: string;
  version?: string;
  author?: string;
  description?: string;
  dependencies?: string[];
}

/** 资源包信息 */
export interface ResourcePackInfo extends ManagedItem {
  type: ManagedItemType.RESOURCE_PACK;
  description?: string;
  packFormat?: number;
}

/** 光影包信息 */
export interface ShaderPackInfo extends ManagedItem {
  type: ManagedItemType.SHADER_PACK;
}

/** 世界存档信息 */
export interface SaveInfo extends ManagedItem {
  type: ManagedItemType.SAVE;
  levelName?: string;
  gameVersion?: string;
  gameMode?: string;
  lastPlayed?: number;
  iconPath?: string;
}

/** 文件统计信息 */
export interface FileStatInfo {
  size: number;
  lastModified: number;
  isDirectory: boolean;
}

/**
 * 资源管理器
 */
export class ResourceManager {
  /** 获取指定类型的目录 */
  static getDirectory(type: ManagedItemType): string {
    const mcDir = FileUtils.getMinecraftDir();
    switch (type) {
      case ManagedItemType.MOD:
        return `${mcDir}/${Constants.MODS_DIR}`;
      case ManagedItemType.RESOURCE_PACK:
        return `${mcDir}/${Constants.RESOURCEPACKS_DIR}`;
      case ManagedItemType.SHADER_PACK:
        return `${mcDir}/${Constants.SHADERPACKS_DIR}`;
      case ManagedItemType.SAVE:
        return `${mcDir}/${Constants.SAVES_DIR}`;
      case ManagedItemType.DATA_PACK:
        return `${mcDir}/datapacks`;
      default:
        return mcDir;
    }
  }

  /** 列出所有项 */
  static listItems(type: ManagedItemType): ManagedItem[] {
    const dir = ResourceManager.getDirectory(type);

    if (!FileUtils.exists(dir)) {
      FileUtils.mkdirs(dir);
      return [];
    }

    const files = FileUtils.listFiles(dir);
    return files.map(name => {
      const path = `${dir}/${name}`;
      const stat = ResourceManager.getFileStat(path);

      return {
        name,
        path,
        size: stat.size,
        lastModified: stat.lastModified,
        isDirectory: stat.isDirectory,
        enabled: !name.endsWith('.disabled'),
        type
      } as ManagedItem;
    }).sort((a, b) => b.lastModified - a.lastModified);
  }

  /** 启用/禁用项 */
  static toggleItem(item: ManagedItem): boolean {
    if (item.enabled) {
      // 禁用: 重命名添加 .disabled
      const newPath = item.path + '.disabled';
      item.enabled = false;
      return FileUtils.copy(item.path, newPath) && FileUtils.delete(item.path);
    } else {
      // 启用: 移除 .disabled
      const newPath = item.path.replace(/\.disabled$/, '');
      item.enabled = true;
      return FileUtils.copy(item.path, newPath) && FileUtils.delete(item.path);
    }
  }

  /** 删除项 */
  static deleteItem(item: ManagedItem): boolean {
    if (item.isDirectory) {
      return FileUtils.delete(item.path);
    }
    try {
      // 使用 FileUtils.delete 处理
      return FileUtils.delete(item.path);
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to delete: ${item.path}`);
      return false;
    }
  }

  /** 获取总占用空间 */
  static getTotalSize(type: ManagedItemType): number {
    const items = ResourceManager.listItems(type);
    return items.reduce((sum, item) => sum + item.size, 0);
  }

  /** 获取项目数量 */
  static getItemCount(type: ManagedItemType): number {
    const dir = ResourceManager.getDirectory(type);
    if (!FileUtils.exists(dir)) {
      return 0;
    }
    return FileUtils.listFiles(dir).length;
  }

  /** 获取文件统计 */
  private static getFileStat(path: string): FileStatInfo {
    const size = FileUtils.getSize(path);
    const isDirectory = FileUtils.isDirectory(path);
    return {
      size: size >= 0 ? size : 0,
      lastModified: Date.now(),
      isDirectory
    };
  }

  // ========== 模组特定逻辑 ==========

  /** 解析模组的元数据 (从 JAR 中的 fabric.mod.json / META-INF/mods.toml 等) */
  static async parseModMetadata(modPath: string): Promise<Partial<ModInfo>> {
    // 模组元数据在 JAR 文件内部，完整解析需要 ZIP 读取
    // 简化实现: 从文件名推断基本信息
    const name = modPath.split('/').pop() ?? '';
    const metadata: Partial<ModInfo> = {
      name,
      path: modPath,
      type: ManagedItemType.MOD
    };

    // 从文件名尝试提取版本信息
    const versionMatch = name.match(/-(\d+\.\d+\.\d+[a-z]?)\.jar$/i);
    if (versionMatch) {
      metadata.version = versionMatch[1];
      metadata.modName = name.substring(0, name.lastIndexOf('-'));
    } else {
      metadata.modName = name.replace('.jar', '').replace('.disabled', '');
    }

    return metadata;
  }

  // ========== 存档特定逻辑 ==========

  /** 解析存档的 level.dat */
  static getSaveInfo(savePath: string): Partial<SaveInfo> {
    const info: Partial<SaveInfo> = {
      path: savePath,
      name: savePath.split('/').pop() ?? '',
      type: ManagedItemType.SAVE,
      isDirectory: true
    };

    // 尝试读取 level.dat 名称 (NBT 格式，这里做简化处理)
    const levelDatPath = `${savePath}/level.dat`;
    if (FileUtils.exists(levelDatPath)) {
      const data = FileUtils.readText(levelDatPath);
      if (data) {
        // 简单字符串匹配提取 LevelName
        const nameMatch = data.match(/LevelName[\s\S]{0,20}([A-Za-z0-9 _-]+)/);
        if (nameMatch) {
          info.levelName = nameMatch[1];
        }
      }
    }

    // 检查图标
    const iconPath = `${savePath}/icon.png`;
    if (FileUtils.exists(iconPath)) {
      info.iconPath = iconPath;
    }

    return info;
  }
}

/**
 * 整合包管理
 * 移植自: FCLCore 的 ModpackHelper + HMCLModpackInstallTask
 */
export class ModpackManager {
  /** 支持的整合包格式 */
  static readonly SUPPORTED_FORMATS = ['HMCL', 'CurseForge', 'Modrinth', 'MultiMC'];

  /** 检测整合包格式 */
  static detectFormat(zipPath: string): string | null {
    // HMCL 格式: 包含 manifest.json 和 overrides 目录
    // CurseForge 格式: 包含 manifest.json (特定结构)
    // Modrinth 格式: 包含 modrinth.index.json
    // MultiMC 格式: 包含 instance.cfg

    if (FileUtils.exists(`${zipPath}/mcbbs.packmeta`)) {
      return 'HMCL';
    }
    if (FileUtils.exists(`${zipPath}/modrinth.index.json`)) {
      return 'Modrinth';
    }
    if (FileUtils.exists(`${zipPath}/instance.cfg`)) {
      return 'MultiMC';
    }

    // 默认尝试 CurseForge 格式
    return 'CurseForge';
  }

  /** 安装整合包 (简化版) */
  static async installModpack(zipPath: string, targetVersionId: string): Promise<boolean> {
    hilog.info(0x0000, TAG, `Installing modpack: ${zipPath} -> ${targetVersionId}`);

    try {
      // 获取目标版本目录
      const versionDir = `${FileUtils.getVersionsDir()}/${targetVersionId}`;
      if (!FileUtils.exists(versionDir)) {
        throw new Error(`Version ${targetVersionId} not found`);
      }

      // 复制模组文件
      const modsSourceDir = `${zipPath}/overrides/mods`;
      const modsTargetDir = `${FileUtils.getMinecraftDir()}/mods`;

      if (FileUtils.exists(modsSourceDir)) {
        FileUtils.mkdirs(modsTargetDir);
        const modFiles = FileUtils.listFiles(modsSourceDir);
        modFiles.forEach(file => {
          FileUtils.copy(`${modsSourceDir}/${file}`, `${modsTargetDir}/${file}`);
        });
      }

      // 复制配置文件
      const configSourceDir = `${zipPath}/overrides/config`;
      const configTargetDir = `${FileUtils.getMinecraftDir()}/config`;
      if (FileUtils.exists(configSourceDir)) {
        FileUtils.mkdirs(configTargetDir);
        const configFiles = FileUtils.listFiles(configSourceDir);
        configFiles.forEach(file => {
          FileUtils.copy(`${configSourceDir}/${file}`, `${configTargetDir}/${file}`);
        });
      }

      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, `Modpack install failed: ${err}`);
      return false;
    }
  }
}
