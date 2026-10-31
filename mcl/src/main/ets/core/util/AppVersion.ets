/**
 * 应用版本常量
 *
 * 版本基线对齐上游 FCL（FCL-Team/FoldCraftLauncher）1.3.4.3，
 * 本项目为 HarmonyOS NEXT 移植分支，附加 -next.N 后缀区分。
 */
export class AppVersion {
  /** 上游 FCL 基线版本 */
  static readonly UPSTREAM_BASE: string = '1.3.4.3';

  /** 本项目版本号（与 AppScope/app.json5 的 versionName 保持一致） */
  static readonly VERSION_NAME: string = '1.3.4.3-next.2';

  /** 本项目 versionCode（与 AppScope/app.json5 的 versionCode 保持一致） */
  static readonly VERSION_CODE: number = 1030404;

  /** 启动器品牌标识（写入 -Dminecraft.launcher.brand） */
  static readonly BRAND: string = 'FCL-HarmonyOS-Next';
}
