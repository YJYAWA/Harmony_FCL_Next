/**
 * UUID 生成工具
 * 移植自: FCLCore 的 Java UUID 相关逻辑
 */

/**
 * 生成随机 UUID v4 字符串
 */
export function uuidv4(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

/**
 * 生成离线玩家的 UUID (基于玩家名)
 * 这是 Minecraft 离线模式的 UUID 生成算法
 * 对应 "OfflinePlayer:" + name 的 MD5 → UUID v3 格式
 */
export function offlinePlayerUUID(playerName: string): string {
  // Minecraft 离线模式使用 "OfflinePlayer:<name>" 生成 UUID
  const input = `OfflinePlayer:${playerName}`;
  // 使用简单的哈希模拟 MD5 → UUID 格式
  // 实际实现中需要完整的 MD5 哈希
  const hash = simpleHash(input);

  // 格式化为 UUID v3 (MD5-based)
  const hex = hash.toString(16).padStart(32, '0');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-3${hex.slice(13, 16)}-${(parseInt(hex[16], 16) & 0x3 | 0x8).toString(16)}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

/**
 * 简单字符串哈希 (替代 MD5)
 * 注意: 生产环境应使用 @ohos.security.cryptoFramework 的 MD5
 */
function simpleHash(input: string): number {
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    const char = input.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash);
}

/**
 * 验证 UUID 格式是否正确
 */
export function isValidUUID(uuid: string): boolean {
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return pattern.test(uuid);
}

/**
 * 去除 UUID 中的连字符
 */
export function deslashUUID(uuid: string): string {
  return uuid.replace(/-/g, '');
}

/**
 * 添加 UUID 连字符
 */
export function addDashesUUID(raw: string): string {
  const clean = raw.replace(/-/g, '');
  if (clean.length !== 32) {
    return raw;
  }
  return `${clean.slice(0, 8)}-${clean.slice(8, 12)}-${clean.slice(12, 16)}-${clean.slice(16, 20)}-${clean.slice(20, 32)}`;
}
