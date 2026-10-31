/**
 * 游戏资源导入 / 导出工具（系统 picker + zlib + fileIo）
 *
 * 移植自 AMCL: entry/src/main/ets/components/GameArchiveIO.ets
 *
 * 统一封装各资源板块的本地导入 / 导出能力：
 *   - importResourceFiles(): 模组 / 资源包 / 光影 / 数据包 —— 多选并逐项导入
 *   - importSaveZips():      存档 —— 多选 .zip，解压并整理成 saves/<世界名>/
 *   - exportSaveZip():       存档 —— 把 saves/<世界名>/ 打包成 .zip 让用户另存
 *
 * 鸿蒙权限要点（与 AMCL 一致）：
 *   - 全部走 DocumentViewPicker，用户显式授权的目录/文件，**不需要**额外的
 *     user_grant 权限弹窗，也不占 READ/WRITE_IMAGEVIDEO；
 *   - picker 返回的是 file://docs/... uri，zlib 需要真实路径，故先拷到 tempDir。
 */
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileUtils } from '../util/FileUtils';

const TAG = 'FCL-GameArchiveIO';

/** 单个文件的导入结果 */
export interface ImportResult {
  ok: boolean;
  /** true = 用户在 picker 里取消，不算失败 */
  cancelled: boolean;
  /** 成功时为落地的文件名 / 世界名；失败时为空 */
  name: string;
  /** 失败原因（toast 用）；成功时为空 */
  message: string;
}

/** 批量导入结果 */
export interface BatchImportResult {
  cancelled: boolean;
  names: string[];
  failures: ImportFailure[];
  message: string;
}

export interface ImportFailure {
  name: string;
  message: string;
}

function okResult(name: string): ImportResult {
  return { ok: true, cancelled: false, name: name, message: '' };
}

function failResult(message: string): ImportResult {
  return { ok: false, cancelled: false, name: '', message: message };
}

function cancelledResult(): ImportResult {
  return { ok: false, cancelled: true, name: '', message: '' };
}

function batchResult(names: string[], failures: ImportFailure[], cancelled: boolean = false): BatchImportResult {
  let message = names.length > 0 ? `已导入 ${names.length} 个文件` : '没有文件导入成功';
  if (failures.length > 0) {
    message += `，${failures.length} 个失败：${failures[0].name} ${failures[0].message}`;
  }
  return { cancelled: cancelled, names: names, failures: failures, message: cancelled ? '' : message };
}

/** 从 picker uri 取末尾文件名（去掉 query，按 / 切，解码一次百分号转义） */
function basenameFromUri(uri: string): string {
  let u = uri;
  const q = u.indexOf('?');
  if (q >= 0) {
    u = u.substring(0, q);
  }
  const slash = u.lastIndexOf('/');
  let name = slash >= 0 ? u.substring(slash + 1) : u;
  try {
    name = decodeURIComponent(name);
  } catch (err) {
    // 保留原值
  }
  return name;
}

/** 去掉文件名扩展名（最后一个 .）。无扩展名则原样返回 */
function stripExt(filename: string): string {
  const dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}

/** 递归 mkdir；已存在不报错 */
function ensureDir(dir: string): void {
  try {
    fs.mkdirSync(dir, true);
  } catch (err) {
    try {
      const st = fs.statSync(dir);
      if (st.isDirectory()) {
        return;
      }
    } catch (inner) {
      // 继续抛
    }
    throw new Error('mkdir failed: ' + (err as BusinessError).message);
  }
}

function pathExists(p: string): boolean {
  try {
    fs.statSync(p);
    return true;
  } catch (err) {
    return false;
  }
}

/** 复制单个 picker uri 指向的文件到 destPath（用 fd，兼容 file://docs/ uri） */
function copyUriToPath(uri: string, destPath: string): void {
  let f: fs.File | null = null;
  try {
    f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    fs.copyFileSync(f.fd, destPath);
  } catch (err) {
    throw new Error('copy from uri failed: ' + (err as BusinessError).message);
  } finally {
    if (f !== null) {
      try {
        fs.closeSync(f);
      } catch (inner) {
        // ignore
      }
    }
  }
}

/** 把 srcPath 文件内容写入 picker 另存 uri（用 fd） */
function copyPathToUri(srcPath: string, uri: string): void {
  let f: fs.File | null = null;
  try {
    f = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.copyFileSync(srcPath, f.fd);
  } catch (err) {
    throw new Error('copy to uri failed: ' + (err as BusinessError).message);
  } finally {
    if (f !== null) {
      try {
        fs.closeSync(f);
      } catch (inner) {
        // ignore
      }
    }
  }
}

/** 把 srcDir 下的每个子项复制进 destDir（destDir 须已存在） */
async function copyTreeInto(srcDir: string, destDir: string): Promise<void> {
  ensureDir(destDir);
  const entries: string[] = fs.listFileSync(srcDir);
  for (const name of entries) {
    const src = `${srcDir}/${name}`;
    const st = fs.statSync(src);
    if (st.isDirectory()) {
      await fs.copyDir(src, destDir, 1);
    } else {
      fs.copyFileSync(src, `${destDir}/${name}`);
    }
  }
}

/** Promise 化 zlib.decompressFile */
function decompress(zipPath: string, destDir: string, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('解压超时'));
    }, timeoutMs);
    try {
      zlib.decompressFile(zipPath, destDir, (err: BusinessError) => {
        clearTimeout(timer);
        if (err && err.code) {
          reject(new Error(err.message));
        } else {
          resolve();
        }
      });
    } catch (err) {
      clearTimeout(timer);
      reject(err as Error);
    }
  });
}

/** Promise 化 zlib.compressFile（压缩目录或文件为 zip） */
function compress(srcPath: string, zipPath: string, timeoutMs: number): Promise<void> {
  const opts: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('压缩超时'));
    }, timeoutMs);
    try {
      zlib.compressFile(srcPath, zipPath, opts, (err: BusinessError) => {
        clearTimeout(timer);
        if (err && err.code) {
          reject(new Error(err.message));
        } else {
          resolve();
        }
      });
    } catch (err) {
      clearTimeout(timer);
      reject(err as Error);
    }
  });
}

export class GameArchiveIO {
  /** 解压 / 压缩超时（存档可能较大，给 300s） */
  private static readonly ZIP_TIMEOUT_MS: number = 300000;

  /**
   * 多选资源文件，逐项校验、导入；一次失败不阻断其他选中项。
   *
   * @param expectedExts 允许的小写扩展名（含点），如 ['.jar'] 或 ['.zip']
   */
  static async importResourceFiles(
    ctx: common.UIAbilityContext,
    targetDir: string,
    expectedExts: string[],
    maxSelectNumber: number = 500
  ): Promise<BatchImportResult> {
    if (targetDir.length === 0) {
      return batchResult([], [{ name: '', message: '目标目录无效' }]);
    }
    let uris: string[] = [];
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = maxSelectNumber;
      if (expectedExts.length > 0) {
        opt.fileSuffixFilters = [expectedExts.join(',')];
      }
      const dp = new picker.DocumentViewPicker(ctx);
      uris = await dp.select(opt);
    } catch (err) {
      return batchResult([], [{ name: '', message: '选择文件失败: ' + (err as BusinessError).message }]);
    }
    if (!uris || uris.length === 0) {
      return batchResult([], [], true);
    }

    const names: string[] = [];
    const failures: ImportFailure[] = [];
    for (let index = 0; index < uris.length; index++) {
      const uri = uris[index];
      const filename = basenameFromUri(uri);
      let temp = '';
      let source: fs.File | null = null;
      try {
        if (filename.length === 0 || filename === '.' || filename === '..' ||
          filename.includes('/') || filename.includes('\\')) {
          throw new Error('文件名无效');
        }
        if (expectedExts.length > 0 &&
          !expectedExts.some((ext: string) => filename.toLowerCase().endsWith(ext))) {
          throw new Error('文件类型不符，需要 ' + expectedExts.join(' / '));
        }
        ensureDir(targetDir);
        // staging 与目标位于同目录；源读取失败时不触碰已有资源文件
        temp = `${targetDir}/.fcl-import-${Date.now()}-${index}-${Math.random()}.tmp`;
        source = await fs.open(uri, fs.OpenMode.READ_ONLY);
        await fs.copyFile(source.fd, temp);
        await fs.rename(temp, `${targetDir}/${filename}`);
        temp = '';
        names.push(filename);
      } catch (err) {
        failures.push({ name: filename, message: (err as BusinessError).message });
      } finally {
        if (source !== null) {
          try {
            fs.closeSync(source);
          } catch (inner) {
            // ignore
          }
        }
        if (temp.length > 0) {
          try {
            fs.unlinkSync(temp);
          } catch (inner) {
            // ignore
          }
        }
      }
    }
    hilog.info(0x0000, TAG, `importResourceFiles selected=${uris.length} ok=${names.length} fail=${failures.length}`);
    return batchResult(names, failures);
  }

  /**
   * 导入存档：选 .zip → 解压 → 整理成 saves/<世界名>/（确保 level.dat 在世界根）。
   *
   * 兼容两种 zip 结构：
   *   - 顶层即世界内容（level.dat 在根）→ 世界名取自 zip 文件名
   *   - 顶层是单个世界文件夹（<世界>/level.dat）→ 世界名取自该文件夹
   * 名称冲突时自动追加 " (1)" / " (2)"。
   */
  static async importSaveZips(
    ctx: common.UIAbilityContext,
    savesDir: string
  ): Promise<BatchImportResult> {
    if (savesDir.length === 0) {
      return batchResult([], [{ name: '', message: '存档目录无效' }]);
    }
    let uris: string[] = [];
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 500;
      opt.fileSuffixFilters = ['.zip'];
      const dp = new picker.DocumentViewPicker(ctx);
      uris = await dp.select(opt);
    } catch (err) {
      return batchResult([], [{ name: '', message: '选择文件失败: ' + (err as BusinessError).message }]);
    }
    if (!uris || uris.length === 0) {
      return batchResult([], [], true);
    }
    const names: string[] = [];
    const failures: ImportFailure[] = [];
    for (const uri of uris) {
      const result = await GameArchiveIO.importSaveUri(ctx, savesDir, uri);
      if (result.ok) {
        names.push(result.name);
      } else {
        failures.push({ name: basenameFromUri(uri), message: result.message });
      }
    }
    return batchResult(names, failures);
  }

  private static async importSaveUri(
    ctx: common.UIAbilityContext,
    savesDir: string,
    uri: string
  ): Promise<ImportResult> {
    const filename = basenameFromUri(uri);
    if (!filename.toLowerCase().endsWith('.zip')) {
      return failResult('存档需为 .zip 文件');
    }

    const stamp = Date.now().toString();
    const tmpZip = `${ctx.tempDir}/fcl_save_${stamp}.zip`;
    const tmpExtract = `${ctx.tempDir}/fcl_save_x_${stamp}`;
    let incompleteTarget = '';
    try {
      // 1. 选中的 zip 拷到沙箱临时路径（zlib 需要真实路径）
      copyUriToPath(uri, tmpZip);
      // 2. 解压到临时目录
      FileUtils.delete(tmpExtract);
      ensureDir(tmpExtract);
      await decompress(tmpZip, tmpExtract, GameArchiveIO.ZIP_TIMEOUT_MS);

      // 3. 定位世界根（含 level.dat 的目录）
      const worldRoot = GameArchiveIO.locateWorldRoot(tmpExtract);
      const defaultName = stripExt(filename);
      let worldName = defaultName;
      if (worldRoot !== tmpExtract) {
        const slash = worldRoot.lastIndexOf('/');
        worldName = slash >= 0 ? worldRoot.substring(slash + 1) : defaultName;
      }
      worldName = GameArchiveIO.sanitizeName(worldName, defaultName);

      // 4. 落地：saves/<worldName>，冲突追加序号
      ensureDir(savesDir);
      const finalName = GameArchiveIO.uniqueName(savesDir, worldName);
      const target = `${savesDir}/${finalName}`;
      incompleteTarget = target;
      await copyTreeInto(worldRoot, target);

      // 5. 校验：level.dat 必须在世界根，否则视为无效存档
      if (!pathExists(`${target}/level.dat`)) {
        FileUtils.delete(target);
        return failResult('zip 内未找到 level.dat，不是有效的 MC 存档');
      }
      incompleteTarget = '';
      return okResult(finalName);
    } catch (err) {
      return failResult('导入失败: ' + (err as BusinessError).message);
    } finally {
      if (incompleteTarget.length > 0) {
        FileUtils.delete(incompleteTarget);
      }
      try {
        fs.unlinkSync(tmpZip);
      } catch (inner) {
        // ignore
      }
      FileUtils.delete(tmpExtract);
    }
  }

  /**
   * 导出存档：把 saves/<worldName>/ 压成 zip → 系统另存 picker 让用户选位置。
   * @returns ok=true 表示已保存
   */
  static async exportSaveZip(
    ctx: common.UIAbilityContext,
    savesDir: string,
    worldName: string
  ): Promise<ImportResult> {
    const worldDir = `${savesDir}/${worldName}`;
    if (!pathExists(worldDir)) {
      return failResult('存档不存在');
    }

    const stamp = Date.now().toString();
    const tmpZip = `${ctx.tempDir}/fcl_export_${stamp}.zip`;
    try {
      try {
        fs.unlinkSync(tmpZip);
      } catch (inner) {
        // ignore
      }
      // 1. 压缩世界目录到临时 zip
      await compress(worldDir, tmpZip, GameArchiveIO.ZIP_TIMEOUT_MS);

      // 2. 另存 picker
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = [`${worldName}.zip`];
      const dp = new picker.DocumentViewPicker(ctx);
      const result = await dp.save(saveOpt);
      if (!result || result.length === 0) {
        return cancelledResult();
      }

      // 3. 临时 zip 内容写入用户选定 uri
      copyPathToUri(tmpZip, result[0]);
      return okResult(worldName);
    } catch (err) {
      return failResult('导出失败: ' + (err as BusinessError).message);
    } finally {
      try {
        fs.unlinkSync(tmpZip);
      } catch (inner) {
        // ignore
      }
    }
  }

  /**
   * 导出单个文件：系统另存 picker，把 srcPath 写入用户选定位置。
   */
  static async exportFile(
    ctx: common.UIAbilityContext,
    srcPath: string,
    fileName: string
  ): Promise<ImportResult> {
    if (!pathExists(srcPath)) {
      return failResult('文件不存在');
    }
    try {
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = [fileName];
      const dp = new picker.DocumentViewPicker(ctx);
      const result = await dp.save(saveOpt);
      if (!result || result.length === 0) {
        return cancelledResult();
      }
      copyPathToUri(srcPath, result[0]);
      return okResult(fileName);
    } catch (err) {
      return failResult('导出失败: ' + (err as BusinessError).message);
    }
  }

  /**
   * 导出文件夹：压成 .zip → 系统另存 picker。
   */
  static async exportDirZip(
    ctx: common.UIAbilityContext,
    srcDir: string,
    dirName: string
  ): Promise<ImportResult> {
    if (!pathExists(srcDir)) {
      return failResult('文件夹不存在');
    }
    const stamp = Date.now().toString();
    const tmpZip = `${ctx.tempDir}/fcl_dir_${stamp}.zip`;
    try {
      try {
        fs.unlinkSync(tmpZip);
      } catch (inner) {
        // ignore
      }
      await compress(srcDir, tmpZip, GameArchiveIO.ZIP_TIMEOUT_MS);
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = [`${dirName}.zip`];
      const dp = new picker.DocumentViewPicker(ctx);
      const result = await dp.save(saveOpt);
      if (!result || result.length === 0) {
        return cancelledResult();
      }
      copyPathToUri(tmpZip, result[0]);
      return okResult(dirName);
    } catch (err) {
      return failResult('导出失败: ' + (err as BusinessError).message);
    } finally {
      try {
        fs.unlinkSync(tmpZip);
      } catch (inner) {
        // ignore
      }
    }
  }

  /**
   * 在解压目录里定位「世界根」：
   *   - root 直接含 level.dat → 返回 root
   *   - root 下有子目录含 level.dat → 返回该子目录
   *   - 都没有 → 返回 root（由调用方做 level.dat 兜底校验）
   */
  private static locateWorldRoot(root: string): string {
    if (pathExists(`${root}/level.dat`)) {
      return root;
    }
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(root);
    } catch (err) {
      return root;
    }
    for (const name of entries) {
      const p = `${root}/${name}`;
      try {
        if (fs.statSync(p).isDirectory() && pathExists(`${p}/level.dat`)) {
          return p;
        }
      } catch (err) {
        // ignore
      }
    }
    return root;
  }

  /** 清理世界名里的非法路径字符；空则回退 fallback */
  private static sanitizeName(name: string, fallback: string): string {
    let n = name.replace(/[\/\\:*?"<>|]/g, '_').trim();
    if (n.length === 0) {
      n = fallback;
    }
    if (n.length === 0) {
      n = 'world';
    }
    return n;
  }

  /** 在 dir 下为 base 取一个不冲突的名字：base / base (1) / base (2) ... */
  private static uniqueName(dir: string, base: string): string {
    if (!pathExists(`${dir}/${base}`)) {
      return base;
    }
    for (let i = 1; i < 1000; i++) {
      const cand = `${base} (${i})`;
      if (!pathExists(`${dir}/${cand}`)) {
        return cand;
      }
    }
    return `${base} (${Date.now()})`;
  }
}
