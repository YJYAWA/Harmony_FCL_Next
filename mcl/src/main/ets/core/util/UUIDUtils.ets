/**
 * UUID 生成工具
 * 移植自: FCLCore 的 Java UUID 相关逻辑
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

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
 *
 * Minecraft 离线模式算法:
 *   1. 取 "OfflinePlayer:<玩家名>" 的 MD5
 *   2. 取前 16 字节
 *   3. 设置 version 位为 3 (name-based UUID)
 *   4. 设置 variant 位为 RFC 4122 (10xx)
 *   5. 格式化为 8-4-4-4-12
 *
 * 上游 FCL (com.tungsten.fclcore.util.UUIDUtils) 使用同一算法,
 * 错误的 UUID 会导致离线模式下存档与服务器数据不匹配。
 */
export function offlinePlayerUUID(playerName: string): string {
  const input = `OfflinePlayer:${playerName}`;
  const hash = md5HexSync(input);
  if (hash.length !== 32) {
    // MD5 计算失败时的兜底 (不常见)
    return '00000000-0000-0000-0000-000000000000';
  }

  // version 3 位: '3' + 后 3 位
  const versionPart = `3${hash.slice(13, 16)}`;
  // variant 位: RFC 4122 → 8/9/a/b
  const variantByte = parseInt(hash.slice(16, 17), 16);
  const variant = ((variantByte & 0x3) | 0x8).toString(16);

  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${versionPart}-${variant}${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}

/**
 * 同步计算字符串的 MD5 (小写 hex)
 *
 * 使用系统 cryptoFramework 的 MD5 实现。
 * ArkTS 的 cryptoFramework 摘要接口为异步, 但离线 UUID 必须在
 * 账号创建等同步路径中可用, 因此这里用纯 JS MD5 实现
 * (与 RFC 1321 一致), 结果与 Java 的 MessageDigest("MD5") 完全相同。
 */
function md5HexSync(input: string): string {
  const bytes = new util.TextEncoder().encodeInto(input);
  return md5Bytes(bytes);
}

/** MD5 常量表 (RFC 1321 定义的 K 值) */
const MD5_K: number[] = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
];

/** 每轮移位量 */
const MD5_SHIFT: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

/**
 * 对字节数组计算 MD5
 */
function md5Bytes(input: Uint8Array): string {
  const originalBitLength = input.length * 8;

  // 补位: 0x80 + 若干 0x00, 直到长度 ≡ 56 (mod 64), 再追加 8 字节长度
  const paddedLength = (((input.length + 8) >> 6) + 1) << 6;
  const buffer = new Uint8Array(paddedLength);
  buffer.set(input);
  buffer[input.length] = 0x80;

  // 长度写为小端 64 位
  const low = originalBitLength >>> 0;
  const high = Math.floor(originalBitLength / 4294967296);
  buffer[paddedLength - 8] = low & 0xff;
  buffer[paddedLength - 7] = (low >>> 8) & 0xff;
  buffer[paddedLength - 6] = (low >>> 16) & 0xff;
  buffer[paddedLength - 5] = (low >>> 24) & 0xff;
  buffer[paddedLength - 4] = high & 0xff;
  buffer[paddedLength - 3] = (high >>> 8) & 0xff;
  buffer[paddedLength - 2] = (high >>> 16) & 0xff;
  buffer[paddedLength - 1] = (high >>> 24) & 0xff;

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  const block = new Int32Array(64);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let i = 0; i < 16; i++) {
      const j = offset + i * 4;
      block[i] = (buffer[j] | (buffer[j + 1] << 8) | (buffer[j + 2] << 16) | (buffer[j + 3] << 24));
    }

    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;

    for (let i = 0; i < 64; i++) {
      let f = 0;
      let g = 0;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }

      f = (f + a + MD5_K[i] + block[g]) | 0;
      a = d;
      d = c;
      c = b;
      b = (b + ((f << MD5_SHIFT[i]) | (f >>> (32 - MD5_SHIFT[i])))) | 0;
    }

    a0 = (a0 + a) | 0;
    b0 = (b0 + b) | 0;
    c0 = (c0 + c) | 0;
    d0 = (d0 + d) | 0;
  }

  return hex32(a0) + hex32(b0) + hex32(c0) + hex32(d0);
}

/** 将 32 位整数输出为 8 位小写 hex */
function hex32(value: number): string {
  let out = '';
  for (let i = 0; i < 4; i++) {
    const byte = (value >>> (i * 8)) & 0xff;
    out += ('0' + byte.toString(16)).slice(-2);
  }
  return out;
}

/**
 * 异步计算字符串的 MD5 (系统 cryptoFramework 实现)
 * 用于需要与系统实现交叉校验的场景
 */
export async function md5Hex(input: string): Promise<string> {
  const bytes = new util.TextEncoder().encodeInto(input);
  const md = cryptoFramework.createMd('MD5');
  const blob: cryptoFramework.DataBlob = { data: bytes };
  await md.update(blob);
  const digest = await md.digest();
  const data = digest.data;
  let hex = '';
  for (let i = 0; i < data.length; i++) {
    hex += ('0' + data[i].toString(16)).slice(-2);
  }
  return hex;
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
