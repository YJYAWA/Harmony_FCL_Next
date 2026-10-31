/**
 * 下载源探测与智能选择
 *
 * 移植自 AMCL: feature_core/src/main/ets/download/SourceProber.ets
 * 保留了 AMCL 的核心判定逻辑（PCL2 规则：官方源可达且 RTT < 4000ms 时官方优先，
 * 否则镜像优先），并把「源」从「BMCLAPI / Mojang 两家」扩展为
 * 「多个 BMCLAPI 镜像节点 + Mojang 官方」—— 对应上游 FCL 1.3.4.x 的
 * BMCLAPI 慢速节点切换能力。
 *
 * 与 AMCL 的差异: AMCL 走引擎自身的 fetchTextEx（cacert + curl_share），
 * 本项目只有 @kit.NetworkKit 的 http，故改用 core/util/HttpUtils 的 httpGet。
 * 探测与实际下载走同一套系统 CA，语义一致。
 */
import { httpGet } from '../util/HttpUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-SourceProber';

export const MOJANG_BASE = 'https://launchermeta.mojang.com/mc/game/version_manifest.json';
export const MOJANG_RESOURCES = 'https://resources.download.minecraft.net';
export const MOJANG_LIBRARIES = 'https://libraries.minecraft.net';

/** BMCLAPI 镜像节点（上游 FCL 的慢速节点切换即基于此列表做测速） */
export const BMCLAPI_NODES: string[] = [
  'https://bmclapi2.bangbang93.com',
  'https://bmclapi3.bangbang93.com'
];

/** 探测结果 */
export interface SourceProbeResult {
  id: string;
  name: string;
  baseUrl: string;
  rttMs: number;
  available: boolean;
  httpStatus: number;
}

/** 源排序结果 */
export interface SourceRanking {
  results: SourceProbeResult[];
  /** 排序后的镜像 baseUrl 列表（最快可用优先） */
  orderedMirrors: string[];
  probedAt: number;
}

const PROBE_TIMEOUT_MS = 8000;
const PROBE_MAX_AGE_MS = 30 * 60 * 1000;
/** PCL2 的 DlPreferMojang 阈值：官方 RTT < 4000ms 时官方优先 */
const PREFER_MOJANG_MAX_RTT_MS = 4000;
/** 探测用的小资源（1 字节 Range） */
const PROBE_ASSET_HASH = 'bdf48ef6b5d0d23bbb02e17d04865216179f510a';
const PROBE_ASSET_PREFIX = 'bd';

let cachedRanking: SourceRanking | null = null;
let probeGeneration: number = 0;
let activeProbe: Promise<SourceRanking> | null = null;

/** 探测单个源 */
async function probeSource(id: string, name: string, baseUrl: string, url: string):
  Promise<SourceProbeResult> {
  const startMs = Date.now();
  const result: SourceProbeResult = {
    id: id, name: name, baseUrl: baseUrl, rttMs: -1, available: false, httpStatus: 0
  };
  try {
    const resp = await httpGet(url, { 'Range': 'bytes=0-0' }, PROBE_TIMEOUT_MS);
    result.httpStatus = resp.status;
    result.rttMs = Date.now() - startMs;
    result.available = resp.status >= 200 && resp.status < 400;
  } catch (err) {
    result.rttMs = Date.now() - startMs;
    result.available = false;
    hilog.warn(0x0000, TAG, `probe ${id} failed: ${err}`);
  }
  return result;
}

/** 探测全部源 */
async function runSourceProbe(generation: number): Promise<SourceRanking> {
  const pending: Promise<SourceProbeResult>[] = [];

  for (const node of BMCLAPI_NODES) {
    pending.push(probeSource(node, `BMCLAPI ${node}`,
      node, `${node}/assets/${PROBE_ASSET_PREFIX}/${PROBE_ASSET_HASH}`));
  }
  pending.push(probeSource('mojang', 'Mojang 官方', MOJANG_RESOURCES,
    `${MOJANG_RESOURCES}/${PROBE_ASSET_PREFIX}/${PROBE_ASSET_HASH}`));

  const results = await Promise.all(pending);

  const mirrors = results.filter(r => r.id !== 'mojang' && r.available)
    .sort((a, b) => a.rttMs - b.rttMs)
    .map(r => r.baseUrl);
  const mojang = results.find(r => r.id === 'mojang');

  // PCL2 规则：官方可达且不慢 → 官方优先；否则镜像优先
  const officialFirst = mojang !== undefined && mojang.available &&
    mojang.rttMs >= 0 && mojang.rttMs < PREFER_MOJANG_MAX_RTT_MS;

  const orderedMirrors: string[] = [];
  if (!officialFirst) {
    for (const m of mirrors) {
      orderedMirrors.push(m);
    }
  }
  // 官方优先时仍保留镜像作为兜底（对齐 PCL2 的 DlSourceOrder：只重排，不删源）
  for (const m of mirrors) {
    if (!orderedMirrors.includes(m)) {
      orderedMirrors.push(m);
    }
  }

  const ranking: SourceRanking = {
    results: results,
    orderedMirrors: orderedMirrors,
    probedAt: Date.now()
  };

  // 两个源都探不通时不写缓存，下次调用重新探测
  if (mirrors.length === 0 && (mojang === undefined || !mojang.available)) {
    hilog.warn(0x0000, TAG, 'all sources unreachable, ranking not cached');
    return ranking;
  }
  if (generation === probeGeneration) {
    cachedRanking = ranking;
  }
  return ranking;
}

/** 探测所有源（同一代次共享进行中的请求） */
export function probeAllSources(): Promise<SourceRanking> {
  if (activeProbe !== null) {
    return activeProbe;
  }
  const generation = probeGeneration;
  const pending = runSourceProbe(generation);
  activeProbe = pending;
  const release = (): void => {
    if (activeProbe === pending) {
      activeProbe = null;
    }
  };
  pending.then(release, release);
  return pending;
}

/** 取缓存的排名（过期返回 null） */
export function getCachedRanking(): SourceRanking | null {
  if (!cachedRanking) {
    return null;
  }
  if (Date.now() - cachedRanking.probedAt > PROBE_MAX_AGE_MS) {
    return null;
  }
  return cachedRanking;
}

/** 取排名（无缓存则探测） */
export async function ensureRanking(): Promise<SourceRanking> {
  const cached = getCachedRanking();
  if (cached) {
    return cached;
  }
  return probeAllSources();
}

/**
 * 获取应优先使用的镜像 baseUrl 列表
 * 空数组表示优先使用官方源
 */
export async function getOrderedMirrors(): Promise<string[]> {
  const ranking = await ensureRanking();
  return ranking.orderedMirrors;
}

/** 同步取缓存中的镜像顺序（不触发探测，供启动等快速路径使用） */
export function getCachedMirrors(): string[] {
  const cached = getCachedRanking();
  return cached ? cached.orderedMirrors : BMCLAPI_NODES.slice();
}

/** 清空缓存 */
export function clearCache(): void {
  probeGeneration++;
  cachedRanking = null;
}
