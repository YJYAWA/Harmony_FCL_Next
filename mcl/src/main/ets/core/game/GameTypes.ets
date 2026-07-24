/**
 * 游戏版本配置和启动类型
 * 移植自: FCLCore 的游戏启动逻辑
 */

/** 游戏版本配置 */
export interface GameVersion {
  /** 版本 ID (如 "1.20.4", "1.21") */
  id: string;
  /** 版本类型 */
  type: VersionType;
  /** 继承自哪个版本 (如 "1.20.4" 客户端继承自原版) */
  inheritsFrom?: string;
  /** 主类名 */
  mainClass: string;
  /** JVM 参数 */
  arguments: GameArguments;
  /** 依赖库列表 */
  libraries: Library[];
  /** 资源索引 */
  assetIndex?: AssetIndex;
  /** Java 版本要求 */
  javaVersion?: JavaVersion;
  /** Forge/Fabric 模组加载器信息 */
  modLoader?: ModLoaderInfo;
  /** 发布日期 */
  releaseTime: string;
}

export enum VersionType {
  RELEASE = 'release',
  SNAPSHOT = 'snapshot',
  OLD_BETA = 'old_beta',
  OLD_ALPHA = 'old_alpha'
}

/** 游戏启动参数 */
export interface GameArguments {
  game: string[];
  jvm: string[];
}

/** 依赖库 */
export interface Library {
  name: string;
  downloads?: LibraryDownloads;
  natives?: Record<string, string>;
  rules?: LibraryRule[];
  url?: string;
}

export interface LibraryDownloads {
  artifact?: Artifact;
  classifiers?: Record<string, Artifact>;
}

export interface Artifact {
  path: string;
  sha1: string;
  size: number;
  url: string;
}

export interface LibraryOS {
  name?: string;
  arch?: string;
  version?: string;
}

export interface LibraryRule {
  action: 'allow' | 'disallow';
  os?: LibraryOS;
  features?: Record<string, boolean>;
}

/** 资源对象 */
export interface AssetObject {
  hash: string;
  size: number;
}

/** 资源索引 */
export interface AssetIndex {
  id: string;
  sha1: string;
  size: number;
  url: string;
  totalSize: number;
}

/** Java 版本要求 */
export interface JavaVersion {
  component: string;
  majorVersion: number;
}

/** 模组加载器信息 */
export interface ModLoaderInfo {
  type: ModLoaderType;
  version: string;
}

export enum ModLoaderType {
  FORGE = 'forge',
  NEOFORGE = 'neoforge',
  FABRIC = 'fabric',
  QUILT = 'quilt',
  LITELOADER = 'liteloader',
  OPTIFINE = 'optifine',
  CLEANROOM = 'cleanroom'
}

/** 游戏启动配置 */
export interface LaunchConfig {
  /** 目标版本 */
  version: string;
  /** 是否启用模组加载器 */
  modLoader?: ModLoaderType;
  /** 模组加载器版本 */
  modLoaderVersion?: string;
  /** 游戏目录 */
  gameDir: string;
  /** Java 运行时路径 */
  javaPath: string;
  /** 最小内存 (MB) */
  minMemory: number;
  /** 最大内存 (MB) */
  maxMemory: number;
  /** 额外 JVM 参数 */
  extraJVMArgs: string[];
  /** 窗口宽度 */
  windowWidth: number;
  /** 窗口高度 */
  windowHeight: number;
  /** 是否为全屏 */
  fullscreen: boolean;
  /** 服务器直连地址 */
  serverAddress?: string;
  /** 账号认证信息 */
  authUsername: string;
  authUUID: string;
  authAccessToken: string;
  /** 是否启用演示模式 */
  demo: boolean;
}

/** 游戏进程状态 */
export interface GameProcessState {
  /** 进程 ID */
  pid: number;
  /** 是否在运行 */
  isRunning: boolean;
  /** 退出码 */
  exitCode?: number;
  /** 启动时间 */
  startTime?: number;
  /** 当前输出行 */
  logLines: string[];
}
