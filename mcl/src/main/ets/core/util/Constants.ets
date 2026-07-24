/**
 * FCLCore 核心常量定义
 * 移植自: FCLCore/src/main/java/com/tungsten/fclcore/util/Constants.java
 */

export class Constants {
  // Minecraft 官方下载源
  static readonly DEFAULT_LIBRARY_URL: string = 'https://libraries.minecraft.net/';
  static readonly DEFAULT_VERSION_DOWNLOAD_URL: string = 'https://bmclapi2.bangbang93.com/versions/';
  static readonly DEFAULT_INDEX_URL: string = 'https://launchermeta.mojang.com/v1/packages/';

  // 资源下载基础 URL
  static readonly DEFAULT_ASSET_BASE_URL: string = 'https://resources.download.minecraft.net/';

  // Mojang API
  static readonly MOJANG_API_URL: string = 'https://api.minecraftservices.com';
  static readonly MOJANG_AUTH_SERVER: string = 'https://authserver.mojang.com';
  static readonly MOJANG_SESSION_SERVER: string = 'https://sessionserver.mojang.com';

  // Microsoft OAuth
  static readonly MICROSOFT_AUTHORIZATION_URL: string =
    'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
  static readonly MICROSOFT_TOKEN_URL: string =
    'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static readonly MICROSOFT_CLIENT_ID: string = '00000000402b5328';
  static readonly MICROSOFT_REDIRECT_URI: string =
    'https://login.microsoftonline.com/common/oauth2/nativeclient';

  // Xbox Live
  static readonly XBOX_AUTH_URL: string = 'https://user.auth.xboxlive.com/user/authenticate';
  static readonly XSTS_AUTH_URL: string = 'https://xsts.auth.xboxlive.com/xsts/authorize';

  // Minecraft 版本元数据
  static readonly VERSION_MANIFEST_URL: string =
    'https://launchermeta.mojang.com/mc/game/version_manifest.json';

  // Fabric
  static readonly FABRIC_META_URL: string = 'https://meta.fabricmc.net/v2/versions';

  // Forge
  static readonly FORGE_MAVEN_URL: string = 'https://files.minecraftforge.net/net/minecraftforge/forge/';

  // BMCLAPI 镜像
  static readonly BMCLAPI_BASE_URL: string = 'https://bmclapi2.bangbang93.com';

  // 文件路径常量
  static readonly MINECRAFT_DIR: string = '.minecraft';
  static readonly VERSIONS_DIR: string = 'versions';
  static readonly LIBRARIES_DIR: string = 'libraries';
  static readonly ASSETS_DIR: string = 'assets';
  static readonly MODS_DIR: string = 'mods';
  static readonly CONFIGS_DIR: string = 'configs';
  static readonly SAVES_DIR: string = 'saves';
  static readonly RESOURCEPACKS_DIR: string = 'resourcepacks';
  static readonly SHADERPACKS_DIR: string = 'shaderpacks';

  // JVM 启动参数
  static readonly DEFAULT_JVM_ARGS: string[] = [
    '-XX:+UseG1GC',
    '-XX:+ParallelRefProcEnabled',
    '-XX:MaxGCPauseMillis=200',
    '-XX:+UnlockExperimentalVMOptions',
    '-XX:+DisableExplicitGC',
    '-XX:+AlwaysPreTouch',
    '-XX:G1NewSizePercent=30',
    '-XX:G1MaxNewSizePercent=40',
    '-XX:G1HeapRegionSize=8M',
    '-XX:G1ReservePercent=20',
    '-XX:G1HeapWastePercent=5',
    '-XX:G1MixedGCCountTarget=4',
    '-XX:InitiatingHeapOccupancyPercent=15',
    '-XX:G1MixedGCLiveThresholdPercent=90',
    '-XX:G1RSetUpdatingPauseTimePercent=5',
    '-XX:SurvivorRatio=32',
    '-XX:+PerfDisableSharedMem',
    '-XX:MaxTenuringThreshold=1'
  ];
}
