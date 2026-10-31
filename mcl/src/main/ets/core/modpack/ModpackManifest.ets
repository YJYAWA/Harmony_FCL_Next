/**
 * 整合包 manifest 数据模型与解析
 *
 * 移植自上游 FCL（FCL-Team/FoldCraftLauncher）FCL/src/main/java/com/tungsten/fclcore/mod/
 * 与 FCL/src/main/java/com/tungsten/fcl/game/：
 *   - McbbsModpackManifest.java  → McbbsManifest
 *   - CurseManifest.java / CurseManifestFile.java / CurseManifestMinecraft.java → CurseManifest
 *   - ModrinthManifest.java → ModrinthManifest
 *   - HMCLModpackManifest.java → HmclManifest
 *   - MultiMCInstanceConfiguration.java → MultiMcManifest
 *   - ModpackHelper.readModpackManifest 的「按顺序尝试各 provider」检测逻辑 → detectType
 *
 * 与 FCL 的差异：
 *   - FCL 用 org.apache.commons.compress 的 ZipFile 直接读 zip 内条目；
 *     本项目 ArkTS 侧没有该库，改为先把 zip 解压到临时目录，再从目录里读文件
 *     （见 ModpackInstaller 的解压步骤），因此本文件只负责「已解压目录 → manifest」的解析。
 *   - FCL 的 Java 泛型/Optional/Stream 用 ArkTS 的 interface + 显式类型替代。
 */
import { fileIo as fs } from '@kit.CoreFileKit';

/** 整合包类型 */
export enum ModpackType {
  MCBBS = 'MCBBS',
  CURSE = 'CurseForge',
  MODRINTH = 'Modrinth',
  HMCL = 'HMCL',
  MULTIMC = 'MultiMC',
  /** 手工整合包：zip 里直接带 .minecraft 目录 */
  MANUAL = 'Manual'
}

/** 需要下载的模组文件 */
export interface ModpackFileEntry {
  /** 目标相对路径（如 mods/xxx.jar、overrides/config/a.toml） */
  path: string;
  /** 下载地址；手工包内文件为空 */
  url: string;
  /** sha1（小写 hex），可选 */
  sha1?: string;
  /** 文件大小（字节），可选 */
  size?: number;
  /** 来自 zip 内（无需下载），可选 */
  extractedPath?: string;
}

/** 解析出的整合包描述 */
export interface ModpackManifest {
  type: ModpackType;
  /** 整合包名称 */
  name: string;
  /** 整合包版本 */
  version: string;
  /** 作者 */
  author: string;
  /** 描述 */
  description: string;
  /** Minecraft 游戏版本（如 1.20.1） */
  gameVersion: string;
  /** 模组加载器（forge / fabric / quilt / none） */
  modLoader: string;
  /** 加载器版本 */
  modLoaderVersion: string;
  /** 需要下载的文件 */
  files: ModpackFileEntry[];
  /** 附加库（MCBBS 的 libraries 段 / MultiMC 的 components） */
  libraries: ModpackLibrary[];
  /** zip 内要解压到游戏根目录的目录名（相对解压根），如 overrides / minecraft */
  overridesDir: string;
  /** 最低内存（MB），0 = 不指定 */
  minMemory: number;
  /** 额外启动参数 */
  launchArguments: string[];
  /** 额外 JVM 参数 */
  javaArguments: string[];
}

/** 整合包附带的库 */
export interface ModpackLibrary {
  name: string;
  /** 下载地址（可选，缺省视为本地库） */
  url?: string;
  /** natives 映射 */
  natives?: Map<string, string>;
}

// ===================== 各格式的原始 JSON 结构 =====================

/** MCBBS manifest.json */
interface McbbsRawManifest {
  manifestType?: string;
  manifestVersion?: number;
  name?: string;
  version?: string;
  author?: string;
  description?: string;
  addons?: McbbsRawAddon[];
  libraries?: McbbsRawLibrary[];
  files?: McbbsRawFile[];
  launchInfo?: McbbsRawLaunchInfo;
}

interface McbbsRawAddon {
  id?: string;
  version?: string;
}

interface McbbsRawLibrary {
  name?: string;
  url?: string;
  natives?: Record<string, string>;
}

interface McbbsRawFile {
  type?: string;
  path?: string;
  hash?: string;
  projectID?: number;
  fileID?: number;
  fileName?: string;
  url?: string;
}

interface McbbsRawLaunchInfo {
  minMemory?: number;
  launchArgument?: string[];
  javaArgument?: string[];
}

/** CurseForge manifest.json */
interface CurseRawManifest {
  manifestType?: string;
  manifestVersion?: number;
  name?: string;
  version?: string;
  author?: string;
  overrides?: string;
  minecraft?: CurseRawMinecraft;
  files?: CurseRawFile[];
}

interface CurseRawMinecraft {
  version?: string;
  modLoaders?: CurseRawModLoader[];
}

interface CurseRawModLoader {
  id?: string;
  version?: string;
}

interface CurseRawFile {
  projectID?: number;
  fileID?: number;
  fileName?: string;
  url?: string;
  required?: boolean;
}

/** Modrinth modrinth.index.json */
interface ModrinthRawManifest {
  game?: string;
  formatVersion?: number;
  versionId?: string;
  name?: string;
  summary?: string;
  files?: ModrinthRawFile[];
  dependencies?: Record<string, string>;
}

interface ModrinthRawFile {
  path?: string;
  hashes?: Record<string, string>;
  env?: Record<string, string>;
  downloads?: string[];
  fileSize?: number;
}

/** HMCL modpack.json */
interface HmclRawManifest {
  name?: string;
  version?: string;
  author?: string;
  description?: string;
  addons?: HmclRawAddon[];
  manifest?: HmclRawInnerManifest;
}

interface HmclRawAddon {
  id?: string;
  version?: string;
}

interface HmclRawInnerManifest {
  version?: string;
}

/** MultiMC instance.cfg */
interface MultiMcRawInstance {
  name?: string;
  iconKey?: string;
  InstanceType?: string;
  MinecraftVersion?: string;
  IntendedVersion?: string;
  JavaPath?: string;
  LaunchMainClass?: string;
  OverrideLaunchArgs?: boolean;
  OverrideJavaArgs?: boolean;
  MinMemAlloc?: number;
  MaxMemAlloc?: number;
  JVMArgs?: string;
  Wrapper?: string;
  Components?: MultiMcRawComponent[];
}

interface MultiMcRawComponent {
  uid?: string;
  version?: string;
}

/** 统一读取 JSON 文本 */
function parseJson<T>(text: string): T | null {
  try {
    return JSON.parse(text) as T;
  } catch (err) {
    return null;
  }
}

/**
 * 判断 zip 解压后的目录属于哪种整合包格式。
 *
 * 对应 FCL ModpackHelper.readModpackManifest 的检测顺序：
 *   MCBBS → Curse → Modrinth → HMCL → MultiMC → 手工包
 */
export function detectModpackType(rootDir: string): ModpackType {
  // MCBBS 的 manifest 可能是 mcbbs.packmeta（优先）或 manifest.json
  // 对应 FCL McbbsModpackProvider.readManifest：先查 mcbbs.packmeta，再查 manifest.json
  const mcbbsMetaText = readTextIfExists(`${rootDir}/mcbbs.packmeta`);
  if (mcbbsMetaText) {
    return ModpackType.MCBBS;
  }

  // MCBBS / CurseForge 都用 manifest.json，靠 manifestType 区分
  const manifestText = readTextIfExists(`${rootDir}/manifest.json`);
  if (manifestText) {
    const raw = parseJson<CurseRawManifest>(manifestText);
    if (raw) {
      // CurseForge 的 manifest 有 minecraft 段（含 version + modLoaders）
      if (raw.minecraft !== undefined) {
        return ModpackType.CURSE;
      }
      // MCBBS 有 addons 段
      const mcbbs = parseJson<McbbsRawManifest>(manifestText);
      if (mcbbs && mcbbs.addons !== undefined) {
        return ModpackType.MCBBS;
      }
      // 只有 manifestType 的按 CurseForge 处理（manifestType = minecraftModpack）
      if (raw.manifestType === 'minecraftModpack') {
        return ModpackType.CURSE;
      }
    }
  }

  // Modrinth
  if (readTextIfExists(`${rootDir}/modrinth.index.json`) !== null) {
    return ModpackType.MODRINTH;
  }

  // HMCL
  if (readTextIfExists(`${rootDir}/modpack.json`) !== null) {
    return ModpackType.HMCL;
  }

  // MultiMC
  if (readTextIfExists(`${rootDir}/instance.cfg`) !== null) {
    return ModpackType.MULTIMC;
  }

  // 手工整合包：目录里能找到 versions 子目录
  if (fileExists(`${rootDir}/.minecraft/versions`) ||
    fileExists(`${rootDir}/versions`)) {
    return ModpackType.MANUAL;
  }

  return ModpackType.MANUAL;
}

function readTextIfExists(path: string): string | null {
  try {
    if (!fs.accessSync(path)) {
      return null;
    }
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      return null;
    }
    return fs.readTextSync(path);
  } catch (err) {
    return null;
  }
}

function fileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (err) {
    return false;
  }
}

// ===================== 各格式解析 =====================

/**
 * 解析整合包 manifest
 * @param rootDir zip 解压后的根目录
 * @param type 整合包类型（可传 null 自动检测）
 */
export function parseModpackManifest(rootDir: string, type?: ModpackType): ModpackManifest | null {
  const resolved = type ?? detectModpackType(rootDir);
  switch (resolved) {
    case ModpackType.MCBBS:
      return parseMcbbs(rootDir);
    case ModpackType.CURSE:
      return parseCurse(rootDir);
    case ModpackType.MODRINTH:
      return parseModrinth(rootDir);
    case ModpackType.HMCL:
      return parseHmcl(rootDir);
    case ModpackType.MULTIMC:
      return parseMultiMc(rootDir);
    default:
      return parseManual(rootDir);
  }
}

/** MCBBS（MCBBS 整合包 / 各类国内整合包最常见格式） */
function parseMcbbs(rootDir: string): ModpackManifest | null {
  // manifest 可能是 mcbbs.packmeta 或 manifest.json（对齐 FCL McbbsModpackProvider）
  let text = readTextIfExists(`${rootDir}/mcbbs.packmeta`);
  if (!text) {
    text = readTextIfExists(`${rootDir}/manifest.json`);
  }
  if (!text) {
    return null;
  }
  const raw = parseJson<McbbsRawManifest>(text);
  if (!raw) {
    return null;
  }

  const files: ModpackFileEntry[] = [];
  const libraries: ModpackLibrary[] = [];

  // addons：Minecraft 版本 + 模组加载器
  let gameVersion = '';
  let modLoader = '';
  let modLoaderVersion = '';
  if (raw.addons) {
    for (const addon of raw.addons) {
      const id = addon.id ?? '';
      if (id === 'minecraft') {
        gameVersion = addon.version ?? '';
      } else if (id === 'forge') {
        modLoader = 'forge';
        modLoaderVersion = addon.version ?? '';
      } else if (id === 'fabric') {
        modLoader = 'fabric';
        modLoaderVersion = addon.version ?? '';
      } else if (id === 'quilt') {
        modLoader = 'quilt';
        modLoaderVersion = addon.version ?? '';
      }
    }
  }

  // libraries
  if (raw.libraries) {
    for (const lib of raw.libraries) {
      const name = lib.name ?? '';
      if (name.length === 0) {
        continue;
      }
      const natives = new Map<string, string>();
      if (lib.natives) {
        const keys = Object.keys(lib.natives);
        for (const key of keys) {
          natives.set(key, lib.natives[key]);
        }
      }
      libraries.push({ name: name, url: lib.url, natives: natives });
    }
  }

  // files：addon 型（zip 内已带，path 相对 overrides） / curse 型（需下载）
  if (raw.files) {
    for (const file of raw.files) {
      if (file.type === 'addon') {
        // zip 内文件：overrides/<path>
        const rel = (file.path ?? '').replace(/^\//, '');
        if (rel.length > 0) {
          files.push({
            path: rel,
            url: '',
            sha1: file.hash,
            extractedPath: `${rootDir}/overrides/${rel}`
          });
        }
      } else if (file.type === 'curse') {
        const projectId = file.projectID ?? 0;
        const fileId = file.fileID ?? 0;
        if (projectId === 0 || fileId === 0) {
          continue;
        }
        // MCBBS 的 curse 条目通常没有 fileName，用 projectID/fileID 拼下载链接
        // （对齐 FCL McbbsModpackManifest.CurseFile.getUrl 的 fallback 规则）
        const url = file.url ?? `https://www.curseforge.com/minecraft/mc-mods/${projectId}/download/${fileId}/file`;
        const fileName = file.fileName ?? `curse_${fileId}.jar`;
        files.push({
          path: `mods/${fileName}`,
          url: url,
          size: undefined
        });
      }
    }
  }

  const launchInfo = raw.launchInfo;
  const minMemory = launchInfo?.minMemory ?? 0;
  const launchArguments: string[] = launchInfo?.launchArgument ?? [];
  const javaArguments: string[] = launchInfo?.javaArgument ?? [];

  return {
    type: ModpackType.MCBBS,
    name: raw.name ?? 'MCBBS Modpack',
    version: raw.version ?? '1.0',
    author: raw.author ?? '',
    description: raw.description ?? '',
    gameVersion: gameVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    files: files,
    libraries: libraries,
    overridesDir: 'overrides',
    minMemory: minMemory,
    launchArguments: launchArguments,
    javaArguments: javaArguments
  };
}

/** CurseForge */
function parseCurse(rootDir: string): ModpackManifest | null {
  const text = readTextIfExists(`${rootDir}/manifest.json`);
  if (!text) {
    return null;
  }
  const raw = parseJson<CurseRawManifest>(text);
  if (!raw) {
    return null;
  }

  const files: ModpackFileEntry[] = [];
  const overrides = raw.overrides ?? 'overrides';

  if (raw.files) {
    for (const file of raw.files) {
      const projectId = file.projectID ?? 0;
      const fileId = file.fileID ?? 0;
      if (projectId === 0 || fileId === 0) {
        continue;
      }
      const fileName = file.fileName ?? `curse_${fileId}.jar`;
      const url = file.url ?? curseDefaultUrl(projectId, fileId, fileName);
      // CurseForge 的文件统一落到实例目录的 mods/ 下
      files.push({
        path: `mods/${fileName}`,
        url: url
      });
    }
  }

  let gameVersion = raw.minecraft?.version ?? '';
  let modLoader = '';
  let modLoaderVersion = '';
  if (raw.minecraft?.modLoaders) {
    for (const loader of raw.minecraft.modLoaders) {
      const id = loader.id ?? '';
      if (id === 'forge' || id === 'forge-legacy') {
        modLoader = 'forge';
      } else if (id === 'fabric') {
        modLoader = 'fabric';
      } else if (id === 'quilt') {
        modLoader = 'quilt';
      } else {
        continue;
      }
      modLoaderVersion = loader.version ?? '';
      break;
    }
  }

  return {
    type: ModpackType.CURSE,
    name: raw.name ?? 'CurseForge Modpack',
    version: raw.version ?? '1.0',
    author: raw.author ?? '',
    description: '',
    gameVersion: gameVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    files: files,
    libraries: [],
    overridesDir: overrides,
    minMemory: 0,
    launchArguments: [],
    javaArguments: []
  };
}

/** Modrinth */
function parseModrinth(rootDir: string): ModpackManifest | null {
  const text = readTextIfExists(`${rootDir}/modrinth.index.json`);
  if (!text) {
    return null;
  }
  const raw = parseJson<ModrinthRawManifest>(text);
  if (!raw) {
    return null;
  }

  const files: ModpackFileEntry[] = [];
  if (raw.files) {
    for (const file of raw.files) {
      const path = file.path ?? '';
      if (path.length === 0) {
        continue;
      }
      let url = '';
      if (file.downloads && file.downloads.length > 0) {
        url = file.downloads[0];
      }
      let sha1: string | undefined = undefined;
      if (file.hashes) {
        const value = file.hashes['sha1'];
        if (value) {
          sha1 = value;
        }
      }
      files.push({
        path: path,
        url: url,
        sha1: sha1,
        size: file.fileSize
      });    }
  }

  const dependencies = raw.dependencies ?? {};
  const gameVersion = dependencies['minecraft'] ?? '';

  return {
    type: ModpackType.MODRINTH,
    name: raw.name ?? 'Modrinth Modpack',
    version: raw.versionId ?? '1.0',
    author: '',
    description: raw.summary ?? '',
    gameVersion: gameVersion,
    modLoader: 'fabric',
    modLoaderVersion: '',
    files: files,
    libraries: [],
    overridesDir: 'overrides',
    minMemory: 0,
    launchArguments: [],
    javaArguments: []
  };
}

/** HMCL */
function parseHmcl(rootDir: string): ModpackManifest | null {
  const text = readTextIfExists(`${rootDir}/modpack.json`);
  if (!text) {
    return null;
  }
  const raw = parseJson<HmclRawManifest>(text);
  if (!raw) {
    return null;
  }

  let gameVersion = raw.manifest?.version ?? '';
  let modLoader = '';
  let modLoaderVersion = '';
  if (raw.addons) {
    for (const addon of raw.addons) {
      const id = addon.id ?? '';
      if (id === 'forge') {
        modLoader = 'forge';
        modLoaderVersion = addon.version ?? '';
      } else if (id === 'fabric') {
        modLoader = 'fabric';
        modLoaderVersion = addon.version ?? '';
      } else if (id === 'minecraft' && gameVersion.length === 0) {
        gameVersion = addon.version ?? '';
      }
    }
  }

  return {
    type: ModpackType.HMCL,
    name: raw.name ?? 'HMCL Modpack',
    version: raw.version ?? '1.0',
    author: raw.author ?? '',
    description: raw.description ?? '',
    gameVersion: gameVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    files: [],
    libraries: [],
    overridesDir: 'minecraft',
    minMemory: 0,
    launchArguments: [],
    javaArguments: []
  };
}

/** MultiMC */
function parseMultiMc(rootDir: string): ModpackManifest | null {
  const text = readTextIfExists(`${rootDir}/instance.cfg`);
  if (!text) {
    return null;
  }
  // MultiMC instance.cfg 是 key=value 的 ini 格式
  const cfg = parseIni(text);
  const components: MultiMcRawComponent[] = [];
  const compSection = cfg['Components'];
  if (compSection) {
    const lines = compSection.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      const idx = trimmed.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      const uid = trimmed.substring(0, idx).trim();
      const version = trimmed.substring(idx + 1).trim();
      components.push({ uid: uid, version: version });
    }
  }

  let gameVersion = cfg['MinecraftVersion'] ?? cfg['IntendedVersion'] ?? '';
  let modLoader = '';
  let modLoaderVersion = '';
  for (const comp of components) {
    const uid = comp.uid ?? '';
    if (uid === 'net.minecraftforge' || uid.startsWith('net.minecraftforge')) {
      modLoader = 'forge';
      modLoaderVersion = comp.version ?? '';
    } else if (uid === 'net.fabricmc.fabric-loader') {
      modLoader = 'fabric';
      modLoaderVersion = comp.version ?? '';
    } else if (uid === 'org.quiltmc.quilt-loader') {
      modLoader = 'quilt';
      modLoaderVersion = comp.version ?? '';
    }
  }

  const minMemory = parseIntSafe(cfg['MinMemAlloc'] ?? '0');
  const jvmArgs = cfg['JVMArgs'] ?? '';
  const javaArguments: string[] = jvmArgs.length > 0 ? jvmArgs.split(' ') : [];

  return {
    type: ModpackType.MULTIMC,
    name: cfg['name'] ?? 'MultiMC Modpack',
    version: '1.0',
    author: '',
    description: '',
    gameVersion: gameVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    files: [],
    libraries: [],
    overridesDir: 'minecraft',
    minMemory: minMemory,
    launchArguments: [],
    javaArguments: javaArguments
  };
}

/** 手工整合包：zip 里直接带 .minecraft 目录 */
function parseManual(rootDir: string): ModpackManifest | null {
  let mcDir = rootDir;
  if (fileExists(`${rootDir}/.minecraft`)) {
    mcDir = `${rootDir}/.minecraft`;
  }
  // 从 versions 子目录里猜游戏版本
  let gameVersion = '';
  const versionsDir = `${mcDir}/versions`;
  try {
    const names = fs.listFileSync(versionsDir);
    for (const name of names) {
      if (name.endsWith('.json')) {
        gameVersion = name.replace(/\.json$/, '');
        break;
      }
    }
  } catch (err) {
    gameVersion = '';
  }

  return {
    type: ModpackType.MANUAL,
    name: 'Modpack',
    version: '1.0',
    author: '',
    description: '',
    gameVersion: gameVersion,
    modLoader: '',
    modLoaderVersion: '',
    files: [],
    libraries: [],
    overridesDir: '',
    minMemory: 0,
    launchArguments: [],
    javaArguments: []
  };
}

/** CurseForge 默认下载地址（无 url 字段时） */
function curseDefaultUrl(projectId: number, fileId: number, fileName?: string): string {
  if (!fileName) {
    return '';
  }
  return `https://edge.forgecdn.net/files/${Math.floor(fileId / 1000)}/${fileId % 1000}/${encodeURIComponent(fileName)}`;
}

/** 解析 ini（MultiMC instance.cfg） */
function parseIni(text: string): Record<string, string> {
  const result: Record<string, string> = {};
  const lines = text.split('\n');
  let currentKey = '';
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    const idx = line.indexOf('=');
    if (idx <= 0) {
      continue;
    }
    const key = line.substring(0, idx).trim();
    const value = line.substring(idx + 1).trim();
    if (key.length === 0) {
      continue;
    }
    // MultiMC 的 Components 是多行同名键，需要拼接
    if (key === currentKey && result[key] !== undefined) {
      result[key] = `${result[key]}\n${value}`;
    } else {
      result[key] = value;
      currentKey = key;
    }
  }
  return result;
}

function parseIntSafe(value: string): number {
  const n = parseInt(value, 10);
  return isNaN(n) ? 0 : n;
}
