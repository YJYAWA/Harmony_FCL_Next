/**
 * 启动配置工厂
 *
 * 集中构建 LaunchConfig，避免 MainPage / VersionsPage / MultiplayerPage
 * 各自硬编码账号信息（此前是 'Player' + 全零 UUID + 'offline' token）。
 */
import { LaunchConfig } from '../game/GameTypes';
import { SettingsManager } from '../SettingsManager';
import { FileUtils } from '../util/FileUtils';
import { AccountService, LaunchAuth } from '../auth/AccountService';

export class LaunchConfigFactory {
  /**
   * 构造启动配置
   * @param version 目标版本 id
   * @param serverAddress 可选直连服务器地址 (host 或 host:port)
   */
  static async create(version: string, serverAddress?: string): Promise<LaunchConfig> {
    const settings = SettingsManager.getInstance();
    const auth: LaunchAuth = await AccountService.getInstance().getLaunchAuth();

    const extraJVMArgs = settings.settings.extraJVMArgs
      .split(' ')
      .filter((a: string): boolean => a.length > 0);

    const config: LaunchConfig = {
      version: version,
      gameDir: settings.settings.gameDir.length > 0
        ? settings.settings.gameDir
        : FileUtils.getMinecraftDir(),
      javaPath: settings.settings.javaPath,
      minMemory: settings.settings.minMemory,
      maxMemory: settings.settings.maxMemory,
      extraJVMArgs: extraJVMArgs,
      windowWidth: settings.settings.windowWidth,
      windowHeight: settings.settings.windowHeight,
      fullscreen: settings.settings.fullscreen,
      authUsername: auth.username,
      authUUID: auth.uuid,
      authAccessToken: auth.accessToken,
      authUserType: auth.userType,
      demo: false
    };

    if (serverAddress !== undefined && serverAddress.length > 0) {
      config.serverAddress = serverAddress;
    }
    return config;
  }
}
