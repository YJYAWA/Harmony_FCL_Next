/**
 * FCL-HarmonyOS 核心模块统一导出
 * 完整复刻 FCLCore + FCL + FCLLibrary 全部功能
 */
// ── 认证 ──
export { Account, AuthInfo, AuthenticationException, AccountType } from './auth/AuthTypes';
export { OfflineAccount } from './auth/OfflineAccount';
export { MicrosoftAccount } from './auth/MicrosoftAccount';
export { YggdrasilAccount, YggdrasilServers } from './auth/YggdrasilAccount';
export { AccountFactory } from './auth/AccountFactory';
export { AccountService, LaunchAuth } from './auth/AccountService';

// ── 下载 ──
export { DownloadProvider, MojangDownloadProvider, BMCLAPIDownloadProvider } from './download/DownloadProvider';
export { DownloadTask, DownloadStatus, DownloadResult, DownloadManager } from './download/DownloadManager';
export { SourceProber, BMCLAPI_NODES, getOrderedMirrors } from './download/SourceProber';

// ── 游戏 ──
export { GameVersion, LaunchConfig, GameProcessState, ModLoaderType } from './game/GameTypes';
export { VersionManager } from './game/VersionManager';
export { ResourceManager, ModpackManager, ManagedItemType } from './game/ModManager';
export { FabricInstaller, ForgeInstaller, OptiFineInstaller } from './game/ModLoaderInstaller';
export { LibraryAnalyzer } from './game/LibraryAnalyzer';
export { GameBuilder } from './game/GameBuilder';
export { LibraryRules, HARMONY_PLATFORM } from './game/LibraryRules';
export { VersionArguments } from './game/VersionArguments';
export { LaunchConfigFactory } from './game/LaunchConfigFactory';
export { parseMavenName, compareMavenVersions } from './game/MavenCoords';

// ── 触控布局 ──
export { ControlType, ControlLayout, ButtonConfig, DirectionConfig, TouchpadConfig,
  DEFAULT_PHONE_LAYOUT } from './control/ControlTypes';
export { ControlLayoutStore, LayoutEntry } from './control/ControlLayoutStore';

// ── 设置 ──
export { SettingsManager, Theme, DownloadSource } from './SettingsManager';
export { ThemeEngine, AccentColor, DarkPalette, LightPalette } from './ThemeEngine';

// ── 存储 ──
export { GameStorage, StorageLocation, parseStorageLocation } from './storage/GameStorage';
export { StorageManager } from './storage/StorageManager';

// ── 归档导入导出 ──
export { GameArchiveIO, ImportResult, BatchImportResult, ImportFailure } from './archive/GameArchiveIO';

// ── 工具 ──
export { Constants } from './util/Constants';
export { AppVersion } from './util/AppVersion';
export { FileUtils } from './util/FileUtils';
export { uuidv4, offlinePlayerUUID } from './util/UUIDUtils';
export { Architecture, ArchType } from './util/Architecture';

// ── 输入 ──
export { KeyCodeConverter, AWTKeyCode, GLFWKeyCode } from './input/KeyCodes';

// ── 服务 ──
export { GameLauncherService } from '../service/GameLauncherService';
export { JarExecutorService } from '../service/JarExecutorService';
