/**
 * 文件系统工具
 * 移植自: FCLCore 的文件操作逻辑
 * 使用 HarmonyOS @ohos.file.fs
 */
import { fileIo as fs, ReadOptions, WriteOptions } from '@kit.CoreFileKit';
import { hash } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../../common/AppContext';

const TAG = 'FCL-FileUtils';

/**
 * 文件工具类
 */
export class FileUtils {
  /** 检查文件是否存在 */
  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch {
      return false;
    }
  }

  /** 检查是否为目录 */
  static isDirectory(path: string): boolean {
    try {
      const stat = fs.statSync(path);
      return stat.isDirectory();
    } catch {
      return false;
    }
  }

  /** 检查是否为文件 */
  static isFile(path: string): boolean {
    try {
      const stat = fs.statSync(path);
      return stat.isFile();
    } catch {
      return false;
    }
  }

  /** 获取文件大小 */
  static getSize(path: string): number {
    try {
      const stat = fs.statSync(path);
      return stat.size;
    } catch {
      return -1;
    }
  }

  /** 创建目录 (递归) */
  static mkdirs(path: string): boolean {
    try {
      fs.mkdirSync(path, true);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to create directory: ${path}, ${error.message}`);
      return false;
    }
  }

  /** 读取文本文件 */
  static readText(path: string): string | null {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);

      const decoder = new TextDecoder('utf-8');
      return decoder.decode(buffer);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to read file: ${path}, ${error.message}`);
      return null;
    }
  }

  /** 写入文本文件 */
  static writeText(path: string, content: string): boolean {
    try {
      // 确保父目录存在
      const parentDir = path.substring(0, path.lastIndexOf('/'));
      if (parentDir && !FileUtils.exists(parentDir)) {
        FileUtils.mkdirs(parentDir);
      }

      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      const encoder = new TextEncoder();
      const buffer = encoder.encodeInto(content);
      fs.writeSync(file.fd, buffer.buffer as ArrayBuffer);
      fs.closeSync(file);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to write file: ${path}, ${error.message}`);
      return false;
    }
  }

  /** 读取 JSON 文件 */
  static readJSON<T>(path: string): T | null {
    try {
      const text = FileUtils.readText(path);
      if (!text) {
        return null;
      }
      return JSON.parse(text) as T;
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to parse JSON: ${path}`);
      return null;
    }
  }

  /** 写入 JSON 文件 */
  static writeJSON(path: string, data: Object): boolean {
    try {
      const text = JSON.stringify(data, null, 2);
      return FileUtils.writeText(path, text);
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to write JSON: ${path}`);
      return false;
    }
  }

  /** 删除文件或目录 */
  static delete(path: string): boolean {
    try {
      if (FileUtils.isDirectory(path)) {
        FileUtils.deleteDirectory(path);
      } else {
        fs.unlinkSync(path);
      }
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to delete: ${path}, ${error.message}`);
      return false;
    }
  }

  /** 递归删除目录 */
  private static deleteDirectory(path: string): void {
    const files = fs.listFileSync(path);
    files.forEach(file => {
      const filePath = `${path}/${file}`;
      if (FileUtils.isDirectory(filePath)) {
        FileUtils.deleteDirectory(filePath);
      } else {
        fs.unlinkSync(filePath);
      }
    });
    fs.rmdirSync(path);
  }

  /** 复制文件 */
  static copy(source: string, dest: string): boolean {
    try {
      // 确保目标父目录存在
      const destDir = dest.substring(0, dest.lastIndexOf('/'));
      if (destDir && !FileUtils.exists(destDir)) {
        FileUtils.mkdirs(destDir);
      }

      fs.copyFileSync(source, dest);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to copy: ${source} -> ${dest}, ${error.message}`);
      return false;
    }
  }

  /** 列出目录内容 */
  static listFiles(path: string): string[] {
    try {
      return fs.listFileSync(path);
    } catch {
      return [];
    }
  }

  /** 获取 Minecraft 数据目录 */
  static getMinecraftDir(): string {
    const gameDir = AppContext.context.filesDir;
    const mcDir = `${gameDir}/.minecraft`;
    if (!FileUtils.exists(mcDir)) {
      FileUtils.mkdirs(mcDir);
    }
    return mcDir;
  }

  /** 获取版本目录 */
  static getVersionsDir(): string {
    const dir = `${FileUtils.getMinecraftDir()}/versions`;
    if (!FileUtils.exists(dir)) {
      FileUtils.mkdirs(dir);
    }
    return dir;
  }

  /** 获取库目录 */
  static getLibrariesDir(): string {
    const dir = `${FileUtils.getMinecraftDir()}/libraries`;
    if (!FileUtils.exists(dir)) {
      FileUtils.mkdirs(dir);
    }
    return dir;
  }

  /** 获取资源目录 */
  static getAssetsDir(): string {
    const dir = `${FileUtils.getMinecraftDir()}/assets`;
    if (!FileUtils.exists(dir)) {
      FileUtils.mkdirs(dir);
    }
    return dir;
  }

  /** 获取模组目录 */
  static getModsDir(): string {
    const dir = `${FileUtils.getMinecraftDir()}/mods`;
    if (!FileUtils.exists(dir)) {
      FileUtils.mkdirs(dir);
    }
    return dir;
  }

  /** 获取文件 SHA1 校验值 */
  static async getFileSHA1(path: string): Promise<string | null> {
    try {
      const content = FileUtils.readText(path);
      if (!content) {
        return null;
      }
      const encoder = new TextEncoder();
      const data = encoder.encodeInto(content);
      const sha1Hash = await hash.hash(data.buffer as ArrayBuffer, 'SHA1');
      return sha1Hash;
    } catch {
      return null;
    }
  }

  /** 格式化文件大小为可读字符串 */
  static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }
}
