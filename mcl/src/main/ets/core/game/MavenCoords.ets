/**
 * Maven 坐标工具
 *
 * 移植自 AMCL: feature_core/src/main/ets/modloader/MavenUtils.ets
 * 取其 parseMavenName / compareMavenVersions 两段核心逻辑，
 * 用于依赖库去重（按 groupId:artifactId(:classifier) 保留最高版本，对齐 PCL2 / HMCL）。
 */

/** Maven 坐标 */
export interface MavenCoordinate {
  groupId: string;
  artifactId: string;
  version: string;
  extension: string;
  classifier?: string;
}

/** 判断是否含控制字符 */
function containsControlCharacter(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 32 || code === 127) {
      return true;
    }
  }
  return false;
}

/** 安全的单段文件名校验 */
function safeBaseName(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  if (text === '.' || text === '..') {
    return false;
  }
  return !containsControlCharacter(text);
}

/**
 * 解析 Maven 坐标
 * 支持 "g:a:v" / "g:a:v:classifier" / "g:a:v@ext" / "g:a:v:classifier@ext"
 */
export function parseMavenName(name: string): MavenCoordinate | null {
  if (name.length === 0 || name.length > 1024 || containsControlCharacter(name) ||
    name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) {
    return null;
  }

  let ext = 'jar';
  let coordStr = name;

  const atIdx = name.indexOf('@');
  if (atIdx >= 0) {
    if (name.indexOf('@', atIdx + 1) >= 0) {
      return null;
    }
    ext = name.substring(atIdx + 1);
    coordStr = name.substring(0, atIdx);
  }

  const parts = coordStr.split(':');
  if (parts.length < 3 || parts.length > 4) {
    return null;
  }
  if (!safeBaseName(ext)) {
    return null;
  }
  for (const part of parts) {
    if (!safeBaseName(part)) {
      return null;
    }
  }
  const groupSegments = parts[0].split('.');
  for (const segment of groupSegments) {
    if (!safeBaseName(segment)) {
      return null;
    }
  }

  const coord: MavenCoordinate = {
    groupId: parts[0],
    artifactId: parts[1],
    version: parts[2],
    extension: ext
  };
  if (parts.length === 4) {
    coord.classifier = parts[3];
  }
  return coord;
}

/**
 * 比较两个 Maven 版本号
 * 返回 1 (a>b) / 0 (相等) / -1 (a<b)
 */
export function compareMavenVersions(a: string, b: string): number {
  if (a === b) {
    return 0;
  }
  const pa = a.split(/[-.+]/);
  const pb = b.split(/[-.+]/);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const sa = i < pa.length ? pa[i] : '';
    const sb = i < pb.length ? pb[i] : '';
    if (sa === sb) {
      continue;
    }
    const na = parseInt(sa, 10);
    const nb = parseInt(sb, 10);
    const aIsNum = sa.length > 0 && !isNaN(na) && String(na) === sa;
    const bIsNum = sb.length > 0 && !isNaN(nb) && String(nb) === sb;
    if (aIsNum && bIsNum) {
      if (na !== nb) {
        return na > nb ? 1 : -1;
      }
    } else if (aIsNum && !bIsNum) {
      return 1;
    } else if (!aIsNum && bIsNum) {
      return -1;
    } else {
      return sa < sb ? -1 : 1;
    }
  }
  return 0;
}
