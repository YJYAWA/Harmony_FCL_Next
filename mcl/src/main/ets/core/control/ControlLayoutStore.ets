/**
 * 触控布局存储
 * 移植自: FCL/control/ 中的 LayoutManager (多布局管理)
 *
 * 功能:
 * - 当前布局的读写 (游戏内覆盖层与编辑器共用同一份数据)
 * - 多布局列表: 复制 / 重命名 / 删除 / 切换
 * - 布局列表持久化到 <filesDir>/fcl_control_layouts.json
 */
import { ControlLayout, ControlType, ButtonConfig, DirectionConfig, TouchpadConfig }
  from './ControlTypes';
import { FileUtils } from '../util/FileUtils';
import { AppContext } from '../../common/AppContext';

const CURRENT_FILE = 'fcl_control_layout.json';
const LIST_FILE = 'fcl_control_layouts.json';

/** 布局列表项 */
export interface LayoutEntry {
  /** 布局 ID (文件名安全化后的名字) */
  id: string;
  /** 显示名 */
  name: string;
}

/**
 * 布局存储
 */
export class ControlLayoutStore {
  /** 读取当前布局 */
  static loadCurrent(): ControlLayout | null {
    const path = `${AppContext.filesDir}/${CURRENT_FILE}`;
    const layout = FileUtils.readJSON<ControlLayout>(path);
    if (!layout) {
      return null;
    }
    // 兼容旧数据: 补齐缺失字段
    if (!layout.buttons) {
      layout.buttons = [];
    }
    if (!layout.directions) {
      layout.directions = [];
    }
    if (!layout.touchpads) {
      layout.touchpads = [];
    }
    if (!layout.version) {
      layout.version = 1;
    }
    return layout;
  }

  /** 保存当前布局 */
  static saveCurrent(layout: ControlLayout): boolean {
    const path = `${AppContext.filesDir}/${CURRENT_FILE}`;
    return FileUtils.writeJSON(path, layout);
  }

  /** 列出全部已保存布局 (含 current) */
  static listLayouts(): LayoutEntry[] {
    const entries: LayoutEntry[] = [];
    const current = ControlLayoutStore.loadCurrent();
    if (current) {
      entries.push({ id: ControlLayoutStore.sanitizeId(current.name), name: current.name });
    }

    const list = FileUtils.readJSON<LayoutEntry[]>(`${AppContext.filesDir}/${LIST_FILE}`);
    if (list) {
      for (const item of list) {
        if (!entries.some(e => e.id === item.id)) {
          entries.push(item);
        }
      }
    }

    // 扫描散落的 fcl_control_layout_*.json
    const files = FileUtils.listFiles(AppContext.filesDir)
      .filter(f => f.startsWith('fcl_control_layout_') && f.endsWith('.json'));
    for (const file of files) {
      const id = file.replace('fcl_control_layout_', '').replace('.json', '');
      if (!entries.some(e => e.id === id)) {
        const saved = FileUtils.readJSON<ControlLayout>(`${AppContext.filesDir}/${file}`);
        entries.push({ id: id, name: saved?.name ?? id });
      }
    }

    return entries;
  }

  /** 保存布局列表 */
  private static saveList(entries: LayoutEntry[]): void {
    FileUtils.writeJSON(`${AppContext.filesDir}/${LIST_FILE}`, entries);
  }

  /** 加载指定布局 */
  static loadById(id: string): ControlLayout | null {
    // 先看 current 是否就是它
    const current = ControlLayoutStore.loadCurrent();
    if (current && ControlLayoutStore.sanitizeId(current.name) === id) {
      return current;
    }
    const path = `${AppContext.filesDir}/fcl_control_layout_${id}.json`;
    const saved = FileUtils.readJSON<ControlLayout>(path);
    return saved;
  }

  /** 切换当前布局 */
  static switchTo(id: string): boolean {
    const layout = ControlLayoutStore.loadById(id);
    if (!layout) {
      return false;
    }
    return ControlLayoutStore.saveCurrent(layout);
  }

  /** 另存为新布局 (复制) */
  static duplicate(sourceName: string, newName: string): boolean {
    const source = ControlLayoutStore.loadCurrent();
    if (!source || newName.trim().length === 0) {
      return false;
    }
    const copy: ControlLayout = {
      name: newName,
      version: source.version,
      deviceType: source.deviceType,
      buttons: ControlLayoutStore.cloneButtons(source.buttons),
      directions: ControlLayoutStore.cloneDirections(source.directions),
      touchpads: ControlLayoutStore.cloneTouchpads(source.touchpads)
    };
    const id = ControlLayoutStore.sanitizeId(newName);
    const path = `${AppContext.filesDir}/fcl_control_layout_${id}.json`;
    if (!FileUtils.writeJSON(path, copy)) {
      return false;
    }
    const entries = ControlLayoutStore.listLayouts();
    if (!entries.some(e => e.id === id)) {
      entries.push({ id: id, name: newName });
      ControlLayoutStore.saveList(entries);
    }
    return true;
  }

  /** 重命名布局 */
  static rename(oldId: string, newName: string): boolean {
    if (newName.trim().length === 0) {
      return false;
    }
    const layout = ControlLayoutStore.loadById(oldId);
    if (!layout) {
      return false;
    }
    layout.name = newName;

    const newId = ControlLayoutStore.sanitizeId(newName);
    // 删除旧文件
    if (oldId !== newId) {
      const oldPath = `${AppContext.filesDir}/fcl_control_layout_${oldId}.json`;
      if (FileUtils.exists(oldPath)) {
        FileUtils.delete(oldPath);
      }
    }
    if (!FileUtils.writeJSON(`${AppContext.filesDir}/fcl_control_layout_${newId}.json`, layout)) {
      return false;
    }

    // 更新列表
    const entries = ControlLayoutStore.listLayouts();
    let found = false;
    for (const e of entries) {
      if (e.id === oldId) {
        e.id = newId;
        e.name = newName;
        found = true;
      }
    }
    if (!found) {
      entries.push({ id: newId, name: newName });
    }
    ControlLayoutStore.saveList(entries);

    // 若重命名的是当前布局, 同步更新 current
    const current = ControlLayoutStore.loadCurrent();
    if (current && ControlLayoutStore.sanitizeId(current.name) === oldId) {
      ControlLayoutStore.saveCurrent(layout);
    }
    return true;
  }

  /** 删除布局 */
  static remove(id: string): boolean {
    const path = `${AppContext.filesDir}/fcl_control_layout_${id}.json`;
    if (FileUtils.exists(path)) {
      FileUtils.delete(path);
    }
    const entries = ControlLayoutStore.listLayouts().filter(e => e.id !== id);
    ControlLayoutStore.saveList(entries);

    const current = ControlLayoutStore.loadCurrent();
    if (current && ControlLayoutStore.sanitizeId(current.name) === id) {
      FileUtils.delete(`${AppContext.filesDir}/${CURRENT_FILE}`);
    }
    return true;
  }

  /** 将名字转换为文件名安全 ID */
  static sanitizeId(name: string): string {
    const cleaned = name.trim().replace(/[^\w一-龥.-]/g, '_');
    return cleaned.length > 0 ? cleaned : 'layout';
  }

  private static cloneButtons(list: ButtonConfig[]): ButtonConfig[] {
    const result: ButtonConfig[] = [];
    for (const item of list) {
      const copy: ButtonConfig = {
        id: item.id, type: ControlType.BUTTON, keyCode: item.keyCode, label: item.label,
        x: item.x, y: item.y, width: item.width, height: item.height,
        color: item.color, opacity: item.opacity, visible: item.visible
      };
      result.push(copy);
    }
    return result;
  }

  private static cloneDirections(list: DirectionConfig[]): DirectionConfig[] {
    const result: DirectionConfig[] = [];
    for (const item of list) {
      const copy: DirectionConfig = {
        id: item.id, type: ControlType.DIRECTION, x: item.x, y: item.y, size: item.size,
        deadZone: item.deadZone, color: item.color, opacity: item.opacity, visible: item.visible
      };
      result.push(copy);
    }
    return result;
  }

  private static cloneTouchpads(list: TouchpadConfig[]): TouchpadConfig[] {
    const result: TouchpadConfig[] = [];
    for (const item of list) {
      const copy: TouchpadConfig = {
        id: item.id, type: ControlType.TOUCHPAD, x: item.x, y: item.y,
        width: item.width, height: item.height,
        sensitivity: item.sensitivity, visible: item.visible
      };
      result.push(copy);
    }
    return result;
  }
}
