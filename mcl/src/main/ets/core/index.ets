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

// ── 下载 ──
export { DownloadProvider, MojangDownloadProvider, BMCLAPIDownloadProvider } from './download/DownloadProvider';
export { DownloadTask, DownloadStatus, DownloadResult, DownloadManager } from './download/DownloadManager';

// ── 游戏 ──
export { GameVersion, LaunchConfig, GameProcessState, ModLoaderType } from './game/GameTypes';
export { VersionManager } from './game/VersionManager';
export { ResourceManager, ModpackManager, ManagedItemType } from './game/ModManager';
export { FabricInstaller, ForgeInstaller, OptiFineInstaller } from './game/ModLoaderInstaller';
export { LibraryAnalyzer } from './game/LibraryAnalyzer';
export { GameBuilder } from './game/GameBuilder';

// ── 设置 ──
export { SettingsManager, Theme, DownloadSource } from './SettingsManager';
export { ThemeEngine, AccentColor, DarkPalette, LightPalette } from './ThemeEngine';

// ── 工具 ──
export { Constants } from './util/Constants';
export { FileUtils } from './util/FileUtils';
export { uuidv4, offlinePlayerUUID } from './util/UUIDUtils';
export { Architecture, ArchType } from './util/Architecture';

// ── 输入 ──
export { KeyCodeConverter, AWTKeyCode, GLFWKeyCode } from './input/KeyCodes';

// ── 更新 ──
export { UpdateChecker } from './upgrade/UpdateChecker';

// ── 服务 ──
export { GameLauncherService } from '../service/GameLauncherService';
export { JarExecutorService } from '../service/JarExecutorService';
