/**
 * MobileGlues 运行时选项
 *
 * 同步上游 FCL 1.3.4.3「内置 MobileGlues 渲染器 + 齿轮入口配置」的能力：
 * 上游把 MobileGlues 全量运行时选项（ANGLE、无错误模式、自定义 GL 版本、
 * GLSL 缓存大小、FSR1 超分、深度清理修复模式等）开放给用户配置，启动时
 * 合并写入 config.json 生效。
 *
 * 本移植版对应落点：
 * - 配置文件路径与原生层一致：<filesDir>/MG/config.json（原生层 MG_DIR_PATH）
 * - 原生层 amcl::mgconfig::PlanMobileGluesConfig 在下次启动时做 schema 归一化，
 *   非默认键会被保留（preservedOverrides），因此这里写入的覆盖项不会被回滚。
 */
import { FileUtils } from './FileUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-MGOptions';

/** MobileGlues 运行时选项键（与 amcl::mgconfig kPreservedIntFields 对齐） */
export class MgOptionKeys {
  static readonly ENABLE_ANGLE: string = 'enableANGLE';
  static readonly ENABLE_NO_ERROR: string = 'enableNoError';
  static readonly CUSTOM_GL_VERSION: string = 'customGLVersion';
  static readonly MAX_GLSL_CACHE_SIZE: string = 'maxGlslCacheSize';
  static readonly ANGLE_DEPTH_CLEAR_FIX: string = 'angleDepthClearFixMode';
  static readonly FSR1_SETTING: string = 'fsr1Setting';
  static readonly EXT_COMPUTE_SHADER: string = 'enableExtComputeShader';
  static readonly EXT_TIMER_QUERY: string = 'enableExtTimerQuery';
  static readonly EXT_DIRECT_STATE_ACCESS: string = 'enableExtDirectStateAccess';
}

/** 选项元数据（名称 + 说明 + 取值范围） */
export class MgOptionMeta {
  key: string = '';
  label: string = '';
  desc: string = '';
  /** 可选值列表 */
  values: number[] = [];
}

function buildMetas(): Array<MgOptionMeta> {
  const list: Array<MgOptionMeta> = [];

  const angle = new MgOptionMeta();
  angle.key = MgOptionKeys.ENABLE_ANGLE;
  angle.label = 'ANGLE 后端';
  angle.desc = '0=禁用（HarmonyOS 必选，AMCL 不附带 ANGLE 库）/ 1=自动 / 2=强制';
  angle.values = [0, 1, 2];
  list.push(angle);

  const noError = new MgOptionMeta();
  noError.key = MgOptionKeys.ENABLE_NO_ERROR;
  noError.label = '无错误模式';
  noError.desc = '0=自动 / 1=开启（忽略 GL 错误）/ 2=关闭 / 3=仅日志';
  noError.values = [0, 1, 2, 3];
  list.push(noError);

  const glVersion = new MgOptionMeta();
  glVersion.key = MgOptionKeys.CUSTOM_GL_VERSION;
  glVersion.label = '自定义 GL 版本';
  glVersion.desc = '0=默认 / 32=GLES 3.2 / 33=GLES 3.3 / 46=GLES 4.6';
  glVersion.values = [0, 32, 33, 46];
  list.push(glVersion);

  const cache = new MgOptionMeta();
  cache.key = MgOptionKeys.MAX_GLSL_CACHE_SIZE;
  cache.label = 'GLSL 缓存 (MiB)';
  cache.desc = '着色器缓存大小上限，0=关闭缓存';
  cache.values = [0, 8, 16, 32, 64, 128, 256];
  list.push(cache);

  const depthFix = new MgOptionMeta();
  depthFix.key = MgOptionKeys.ANGLE_DEPTH_CLEAR_FIX;
  depthFix.label = '深度清理修复';
  depthFix.desc = '0=关闭 / 1=开启 / 2=激进模式（ANGLE 深度缓冲异常时尝试）';
  depthFix.values = [0, 1, 2];
  list.push(depthFix);

  const fsr = new MgOptionMeta();
  fsr.key = MgOptionKeys.FSR1_SETTING;
  fsr.label = 'FSR1 超分';
  fsr.desc = '0=禁用 / 1~3=质量档位';
  fsr.values = [0, 1, 2, 3];
  list.push(fsr);

  const compute = new MgOptionMeta();
  compute.key = MgOptionKeys.EXT_COMPUTE_SHADER;
  compute.label = 'Compute Shader 扩展';
  compute.desc = '0=禁用 / 1=启用';
  compute.values = [0, 1];
  list.push(compute);

  const timer = new MgOptionMeta();
  timer.key = MgOptionKeys.EXT_TIMER_QUERY;
  timer.label = 'Timer Query 扩展';
  timer.desc = '0=禁用 / 1=启用';
  timer.values = [0, 1];
  list.push(timer);

  const dsa = new MgOptionMeta();
  dsa.key = MgOptionKeys.EXT_DIRECT_STATE_ACCESS;
  dsa.label = 'Direct State Access 扩展';
  dsa.desc = '0=禁用 / 1=启用';
  dsa.values = [0, 1];
  list.push(dsa);

  return list;
}

export class MgOptions {
  /** 全部可配置项元数据 */
  static readonly METAS: Array<MgOptionMeta> = buildMetas();

  /** MobileGlues 配置文件路径 */
  static configPath(filesDir: string): string {
    return `${filesDir}/MG/config.json`;
  }

  /**
   * 读取当前生效的选项值
   * @param filesDir 应用沙箱 files 目录
   * @returns 键 → 值的映射（仅包含配置中显式存在的键）
   */
  static readOverrides(filesDir: string): Map<string, number> {
    const result: Map<string, number> = new Map<string, number>();
    const raw = FileUtils.readText(MgOptions.configPath(filesDir));
    if (!raw) {
      return result;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      for (const meta of MgOptions.METAS) {
        const value = parsed[meta.key];
        if (typeof value === 'number' && Number.isInteger(value)) {
          result.set(meta.key, value);
        }
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, `Failed to parse MG config: ${err}`);
    }
    return result;
  }

  /**
   * 合并写入选项（仅写入显式配置过的键，保留 MG 自管键）
   * @param filesDir 应用沙箱 files 目录
   * @param overrides 键 → 值
   * @returns 是否写入成功
   */
  static writeOverrides(filesDir: string, overrides: Map<string, number>): boolean {
    const path = MgOptions.configPath(filesDir);
    const root: Record<string, Object> = {};
    const raw = FileUtils.readText(path);
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as Record<string, Object>;
        if (parsed) {
          for (const key of Object.keys(parsed)) {
            root[key] = parsed[key];
          }
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, `MG config malformed, starting fresh: ${err}`);
      }
    }

    overrides.forEach((value: number, key: string) => {
      if (Number.isInteger(value)) {
        root[key] = value;
      }
    });

    const text = `${JSON.stringify(root, null, 2)}\n`;
    const ok = FileUtils.writeText(path, text);
    hilog.info(0x0000, TAG, `MG config updated (${overrides.size} keys): ${ok}`);
    return ok;
  }

  /** 清除所有用户覆盖项（恢复出厂预设） */
  static clearOverrides(filesDir: string): boolean {
    const path = MgOptions.configPath(filesDir);
    if (!FileUtils.exists(path)) {
      return true;
    }
    return FileUtils.delete(path);
  }
}
