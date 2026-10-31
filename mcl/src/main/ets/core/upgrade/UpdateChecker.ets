/**
 * 更新检查器
 * 移植自: FCL/upgrade/UpdateChecker + RemoteVersion
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-UpdateChecker';

/** 远程版本信息 */
export interface RemoteVersionInfo {
  versionName: string;
  versionCode: number;
  changelog: string;
  downloadUrl: string;
  releaseDate: string;
  mandatory: boolean;
}

/** 更新检查结果 */
export interface UpdateCheckResult {
  hasUpdate: boolean;
  currentVersion: string;
  latestVersion?: RemoteVersionInfo;
  downloadSize?: number;
}

/**
 * 更新检查器
 */
export class UpdateChecker {
  private static readonly UPDATE_URL =
    'https://api.github.com/repos/FCL-Team/FoldCraftLauncher/releases/latest';
  private static readonly CURRENT_VERSION = '1.0.0';
  private static readonly CURRENT_VERSION_CODE = 1000000;

  /**
   * 检查更新
   */
  static async check(): Promise<UpdateCheckResult> {
    try {
      hilog.info(0x0000, TAG, 'Checking for updates...');

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(UpdateChecker.UPDATE_URL, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/vnd.github.v3+json' },
        connectTimeout: 10000,
        readTimeout: 15000
      });
      httpRequest.destroy();

      if (response.responseCode !== 200) {
        return { hasUpdate: false, currentVersion: UpdateChecker.CURRENT_VERSION };
      }

      const release = JSON.parse(response.result as string) as Record<string, Object>;
      const tagName = (release['tag_name'] as string) ?? '';

      // 比较版本
      const latestVersion = tagName.replace('v', '');
      const latestCode = parseInt((release['id'] as string) ?? '0');

      if (latestCode > UpdateChecker.CURRENT_VERSION_CODE ||
        UpdateChecker.compareVersions(latestVersion, UpdateChecker.CURRENT_VERSION) > 0) {

        const asset = (release['assets'] as Array<Record<string, Object>>)?.[0];

        return {
          hasUpdate: true,
          currentVersion: UpdateChecker.CURRENT_VERSION,
          latestVersion: {
            versionName: latestVersion,
            versionCode: latestCode,
            changelog: (release['body'] as string) ?? '',
            downloadUrl: (asset?.['browser_download_url'] as string) ?? '',
            releaseDate: (release['published_at'] as string) ?? '',
            mandatory: false
          },
          downloadSize: (asset?.['size'] as number)
        };
      }

      return { hasUpdate: false, currentVersion: UpdateChecker.CURRENT_VERSION };

    } catch (err) {
      hilog.warn(0x0000, TAG, `Update check failed: ${err}`);
      return { hasUpdate: false, currentVersion: UpdateChecker.CURRENT_VERSION };
    }
  }

  /**
   * 比较两个语义化版本号
   */
  static compareVersions(a: string, b: string): number {
    const partsA = a.split('.').map(Number);
    const partsB = b.split('.').map(Number);

    for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
      const pa = partsA[i] ?? 0;
      const pb = partsB[i] ?? 0;
      if (pa > pb) {
        return 1;
      }
      if (pa < pb) {
        return -1;
      }
    }
    return 0;
  }

  /** 获取当前版本字符串 */
  static getCurrentVersion(): string {
    return UpdateChecker.CURRENT_VERSION;
  }
}
