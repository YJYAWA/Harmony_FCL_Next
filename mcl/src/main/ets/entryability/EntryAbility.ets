/**
 * FCL-HarmonyOS 入口 Ability
 * 对应 Android 的 MainActivity
 */
import { UIAbility, Want, AbilityConstant, common, abilityAccessCtrl, Permissions, Configuration, ConfigurationConstant }
  from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from '../common/AppContext';
import { StorageManager } from '../core/storage/StorageManager';
import { GameStorage } from '../core/storage/GameStorage';

const TAG = 'FCL-EntryAbility';

/** picker 授权持久化权限（让已授权的公共目录跨重启仍可访问） */
const FILE_PERSIST_PERM: Permissions = 'ohos.permission.FILE_ACCESS_PERSIST';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'EntryAbility onCreate');
    AppContext.init(this.context);

    // 系统深色模式（供 ThemeEngine 的 SYSTEM 模式读取）
    AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode',
      this.context.config.colorMode);

    // 存储位置：必须在任何 FileUtils.getMinecraftDir() 之前加载完成，
    // 否则会读到错误的根目录
    StorageManager.getInstance().initialize();

    // 鸿蒙权限要点：
    //   - READ_WRITE_DOWNLOAD_DIRECTORY 只在用户主动切「游戏数据位置 → 沙箱外」时申请
    //     （见 StorageManager.setStorageLocation），避免一启动就弹权限框；
    //   - FILE_ACCESS_PERSIST 同样只在此时申请，用来让已授权目录跨重启仍可访问；
    //   - 资源导入 / 存档导出走 DocumentViewPicker（用户显式授权），不需要额外的
    //     user_grant 权限，故不声明 READ/WRITE_IMAGEVIDEO。
    this.requestPersistPermission();
  }

  /**
   * 运行时申请 picker 授权持久化权限
   * 失败不阻断启动 —— 外部存储会自动回落沙箱
   */
  private async requestPersistPermission(): Promise<void> {
    try {
      const atm = abilityAccessCtrl.createAtManager();
      const res = await atm.requestPermissionsFromUser(
        this.context as common.UIAbilityContext, [FILE_PERSIST_PERM]);
      hilog.info(0x0000, TAG,
        `FILE_ACCESS_PERSIST -> ${res.authResults[0] === 0 ? 'granted' : 'denied'}`);
    } catch (err) {
      hilog.warn(0x0000, TAG, `requestPersistPermission failed: ${err}`);
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');

    // 写一份说明文件引导用户开启「显示隐藏文件」（沙箱内外都写）
    GameStorage.writeHints();

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(0x0000, TAG, `Failed to load content: ${err.code} ${err.message}`);
        return;
      }
      hilog.info(0x0000, TAG, 'Content loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'onBackground');
  }

  /** 系统深浅色切换时同步给 UI（ThemeEngine 的 SYSTEM 模式） */
  onConfigurationUpdate(newConfig: Configuration): void {
    const current: ConfigurationConstant.ColorMode | undefined = AppStorage.get('currentColorMode');
    if (current !== newConfig.colorMode) {
      AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode', newConfig.colorMode);
      hilog.info(0x0000, TAG, `colorMode changed -> ${newConfig.colorMode}`);
    }
  }
}
