/**
 * 键盘/鼠标/手柄键码映射表
 * 移植自: FCLauncher/keycodes/ (AWTInputEvent, LwjglGlfwKeycode, GamepadKeycodeMap 等)
 *
 * 包含:
 * - Minecraft 键位绑定 → AWT/GLFW/Android 键码映射
 * - 常用游戏操作对应的默认按键
 * - 手柄按键映射
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-KeyCodes';

/** AWT 键盘码常量 (java.awt.event.KeyEvent) */
export enum AWTKeyCode {
  VK_ESCAPE = 27,
  VK_ENTER = 10,
  VK_SPACE = 32,
  VK_TAB = 9,
  VK_SHIFT = 16,
  VK_CONTROL = 17,
  VK_ALT = 18,
  VK_CAPS_LOCK = 20,
  VK_BACK_SPACE = 8,
  VK_DELETE = 127,
  VK_INSERT = 155,
  VK_HOME = 36,
  VK_END = 35,
  VK_PAGE_UP = 33,
  VK_PAGE_DOWN = 34,
  VK_LEFT = 37,
  VK_UP = 38,
  VK_RIGHT = 39,
  VK_DOWN = 40,
  VK_F1 = 112, VK_F2 = 113, VK_F3 = 114, VK_F4 = 115,
  VK_F5 = 116, VK_F6 = 117, VK_F7 = 118, VK_F8 = 119,
  VK_F9 = 120, VK_F10 = 121, VK_F11 = 122, VK_F12 = 123,
  VK_0 = 48, VK_1 = 49, VK_2 = 50, VK_3 = 51, VK_4 = 52,
  VK_5 = 53, VK_6 = 54, VK_7 = 55, VK_8 = 56, VK_9 = 57,
  VK_A = 65, VK_B = 66, VK_C = 67, VK_D = 68, VK_E = 69,
  VK_F = 70, VK_G = 71, VK_H = 72, VK_I = 73, VK_J = 74,
  VK_K = 75, VK_L = 76, VK_M = 77, VK_N = 78, VK_O = 79,
  VK_P = 80, VK_Q = 81, VK_R = 82, VK_S = 83, VK_T = 84,
  VK_U = 85, VK_V = 86, VK_W = 87, VK_X = 88, VK_Y = 89,
  VK_Z = 90,
  VK_NUMPAD0 = 96, VK_NUMPAD1 = 97, VK_NUMPAD2 = 98, VK_NUMPAD3 = 99,
  VK_NUMPAD4 = 100, VK_NUMPAD5 = 101, VK_NUMPAD6 = 102, VK_NUMPAD7 = 103,
  VK_NUMPAD8 = 104, VK_NUMPAD9 = 105,
  VK_LEFT_SHIFT = 340, VK_RIGHT_SHIFT = 344,
  VK_LEFT_CONTROL = 341, VK_RIGHT_CONTROL = 345,
  VK_PRINTSCREEN = 154, VK_SCROLL_LOCK = 145, VK_PAUSE = 19,
  VK_SLASH = 47, VK_BACK_SLASH = 92,
  VK_COMMA = 44, VK_PERIOD = 46, VK_MINUS = 45, VK_EQUALS = 61,
  VK_SEMICOLON = 59, VK_QUOTE = 222,
  VK_OPEN_BRACKET = 91, VK_CLOSE_BRACKET = 93
}

/** 鼠标按钮 AWT 码 */
export enum AWTMouseButton {
  BUTTON1 = 1,  // 左键
  BUTTON2 = 2,  // 中键
  BUTTON3 = 3   // 右键
}

/** GLFW 键码 */
export enum GLFWKeyCode {
  GLFW_KEY_SPACE = 32,
  GLFW_KEY_APOSTROPHE = 39,
  GLFW_KEY_COMMA = 44,
  GLFW_KEY_MINUS = 45,
  GLFW_KEY_PERIOD = 46,
  GLFW_KEY_SLASH = 47,
  GLFW_KEY_0 = 48, GLFW_KEY_1 = 49, GLFW_KEY_2 = 50, GLFW_KEY_3 = 51, GLFW_KEY_4 = 52,
  GLFW_KEY_5 = 53, GLFW_KEY_6 = 54, GLFW_KEY_7 = 55, GLFW_KEY_8 = 56, GLFW_KEY_9 = 57,
  GLFW_KEY_SEMICOLON = 59,
  GLFW_KEY_EQUAL = 61,
  GLFW_KEY_A = 65, GLFW_KEY_B = 66, GLFW_KEY_C = 67, GLFW_KEY_D = 68, GLFW_KEY_E = 69,
  GLFW_KEY_F = 70, GLFW_KEY_G = 71, GLFW_KEY_H = 72, GLFW_KEY_I = 73, GLFW_KEY_J = 74,
  GLFW_KEY_K = 75, GLFW_KEY_L = 76, GLFW_KEY_M = 77, GLFW_KEY_N = 78, GLFW_KEY_O = 79,
  GLFW_KEY_P = 80, GLFW_KEY_Q = 81, GLFW_KEY_R = 82, GLFW_KEY_S = 83, GLFW_KEY_T = 84,
  GLFW_KEY_U = 85, GLFW_KEY_V = 86, GLFW_KEY_W = 87, GLFW_KEY_X = 88, GLFW_KEY_Y = 89,
  GLFW_KEY_Z = 90,
  GLFW_KEY_ESCAPE = 256, GLFW_KEY_ENTER = 257, GLFW_KEY_TAB = 258,
  GLFW_KEY_BACKSPACE = 259, GLFW_KEY_INSERT = 260, GLFW_KEY_DELETE = 261,
  GLFW_KEY_RIGHT = 262, GLFW_KEY_LEFT = 263, GLFW_KEY_DOWN = 264, GLFW_KEY_UP = 265,
  GLFW_KEY_PAGE_UP = 266, GLFW_KEY_PAGE_DOWN = 267, GLFW_KEY_HOME = 268, GLFW_KEY_END = 269,
  GLFW_KEY_LEFT_SHIFT = 340, GLFW_KEY_LEFT_CONTROL = 341, GLFW_KEY_LEFT_ALT = 342,
  GLFW_KEY_RIGHT_SHIFT = 344, GLFW_KEY_RIGHT_CONTROL = 345, GLFW_KEY_RIGHT_ALT = 346,
  GLFW_KEY_F1 = 290, GLFW_KEY_F2 = 291, GLFW_KEY_F3 = 292, GLFW_KEY_F4 = 293,
  GLFW_KEY_F5 = 294, GLFW_KEY_F6 = 295, GLFW_KEY_F7 = 296, GLFW_KEY_F8 = 297,
  GLFW_KEY_F9 = 298, GLFW_KEY_F10 = 299, GLFW_KEY_F11 = 300, GLFW_KEY_F12 = 301,
  GLFW_KEY_KP_0 = 320, GLFW_KEY_KP_1 = 321, GLFW_KEY_KP_2 = 322, GLFW_KEY_KP_3 = 323,
  GLFW_KEY_KP_4 = 324, GLFW_KEY_KP_5 = 325, GLFW_KEY_KP_6 = 326, GLFW_KEY_KP_7 = 327,
  GLFW_KEY_KP_8 = 328, GLFW_KEY_KP_9 = 329
}

/** GLFW 鼠标按钮 */
export enum GLFWMouseButton {
  GLFW_MOUSE_BUTTON_1 = 0,
  GLFW_MOUSE_BUTTON_2 = 1,
  GLFW_MOUSE_BUTTON_3 = 2
}

/** Minecraft 默认键位绑定 */
export interface MinecraftKeyBinding {
  /** 操作名称 (如 "key.forward") */
  name: string;
  /** 默认 GLFW 键码 */
  defaultKey: number;
  /** 分类 */
  category: KeyCategory;
  /** 中文描述 */
  description: string;
}

export enum KeyCategory {
  MOVEMENT = 'movement',
  GAMEPLAY = 'gameplay',
  INVENTORY = 'inventory',
  MULTIPLAYER = 'multiplayer',
  UI = 'ui',
  MISC = 'misc'
}

/** Minecraft 默认键位绑定表 */
export const MINECRAFT_DEFAULT_BINDINGS: MinecraftKeyBinding[] = [
  { name: 'key.forward', defaultKey: GLFWKeyCode.GLFW_KEY_W, category: KeyCategory.MOVEMENT, description: '前进' },
  { name: 'key.left', defaultKey: GLFWKeyCode.GLFW_KEY_A, category: KeyCategory.MOVEMENT, description: '左移' },
  { name: 'key.back', defaultKey: GLFWKeyCode.GLFW_KEY_S, category: KeyCategory.MOVEMENT, description: '后退' },
  { name: 'key.right', defaultKey: GLFWKeyCode.GLFW_KEY_D, category: KeyCategory.MOVEMENT, description: '右移' },
  { name: 'key.jump', defaultKey: GLFWKeyCode.GLFW_KEY_SPACE, category: KeyCategory.MOVEMENT, description: '跳跃' },
  { name: 'key.sneak', defaultKey: GLFWKeyCode.GLFW_KEY_LEFT_SHIFT, category: KeyCategory.MOVEMENT, description: '潜行' },
  { name: 'key.sprint', defaultKey: GLFWKeyCode.GLFW_KEY_LEFT_CONTROL, category: KeyCategory.MOVEMENT, description: '疾跑' },
  { name: 'key.inventory', defaultKey: GLFWKeyCode.GLFW_KEY_E, category: KeyCategory.INVENTORY, description: '物品栏' },
  { name: 'key.drop', defaultKey: GLFWKeyCode.GLFW_KEY_Q, category: KeyCategory.GAMEPLAY, description: '丢弃物品' },
  { name: 'key.chat', defaultKey: GLFWKeyCode.GLFW_KEY_T, category: KeyCategory.MULTIPLAYER, description: '聊天' },
  { name: 'key.command', defaultKey: GLFWKeyCode.GLFW_KEY_SLASH, category: KeyCategory.MULTIPLAYER, description: '命令' },
  { name: 'key.playerlist', defaultKey: GLFWKeyCode.GLFW_KEY_TAB, category: KeyCategory.MULTIPLAYER, description: '玩家列表' },
  { name: 'key.attack', defaultKey: -100, category: KeyCategory.GAMEPLAY, description: '攻击/破坏 (鼠标左键)' },
  { name: 'key.use', defaultKey: -99, category: KeyCategory.GAMEPLAY, description: '使用/放置 (鼠标右键)' },
  { name: 'key.pickItem', defaultKey: -98, category: KeyCategory.GAMEPLAY, description: '选取方块 (鼠标中键)' },
  { name: 'key.swapOffhand', defaultKey: GLFWKeyCode.GLFW_KEY_F, category: KeyCategory.GAMEPLAY, description: '交换副手' },
  { name: 'key.hotbar.1', defaultKey: GLFWKeyCode.GLFW_KEY_1, category: KeyCategory.INVENTORY, description: '快捷栏 1' },
  { name: 'key.hotbar.2', defaultKey: GLFWKeyCode.GLFW_KEY_2, category: KeyCategory.INVENTORY, description: '快捷栏 2' },
  { name: 'key.hotbar.3', defaultKey: GLFWKeyCode.GLFW_KEY_3, category: KeyCategory.INVENTORY, description: '快捷栏 3' },
  { name: 'key.hotbar.4', defaultKey: GLFWKeyCode.GLFW_KEY_4, category: KeyCategory.INVENTORY, description: '快捷栏 4' },
  { name: 'key.hotbar.5', defaultKey: GLFWKeyCode.GLFW_KEY_5, category: KeyCategory.INVENTORY, description: '快捷栏 5' },
  { name: 'key.hotbar.6', defaultKey: GLFWKeyCode.GLFW_KEY_6, category: KeyCategory.INVENTORY, description: '快捷栏 6' },
  { name: 'key.hotbar.7', defaultKey: GLFWKeyCode.GLFW_KEY_7, category: KeyCategory.INVENTORY, description: '快捷栏 7' },
  { name: 'key.hotbar.8', defaultKey: GLFWKeyCode.GLFW_KEY_8, category: KeyCategory.INVENTORY, description: '快捷栏 8' },
  { name: 'key.hotbar.9', defaultKey: GLFWKeyCode.GLFW_KEY_9, category: KeyCategory.INVENTORY, description: '快捷栏 9' },
  { name: 'key.screenshot', defaultKey: GLFWKeyCode.GLFW_KEY_F2, category: KeyCategory.MISC, description: '截图' },
  { name: 'key.togglePerspective', defaultKey: GLFWKeyCode.GLFW_KEY_F5, category: KeyCategory.MISC, description: '切换视角' },
  { name: 'key.fullscreen', defaultKey: GLFWKeyCode.GLFW_KEY_F11, category: KeyCategory.MISC, description: '全屏' },
  { name: 'key.smoothCamera', defaultKey: GLFWKeyCode.GLFW_KEY_F4, category: KeyCategory.MISC, description: '平滑镜头' },
  { name: 'key.advancements', defaultKey: GLFWKeyCode.GLFW_KEY_L, category: KeyCategory.UI, description: '进度' },
  { name: 'key.socialInteractions', defaultKey: GLFWKeyCode.GLFW_KEY_P, category: KeyCategory.MULTIPLAYER, description: '社交' },
  { name: 'key.saveToolbar', defaultKey: GLFWKeyCode.GLFW_KEY_C, category: KeyCategory.INVENTORY, description: '保存工具栏' },
  { name: 'key.loadToolbar', defaultKey: GLFWKeyCode.GLFW_KEY_X, category: KeyCategory.INVENTORY, description: '加载工具栏' },
  { name: 'key.spectatorOutlines', defaultKey: GLFWKeyCode.GLFW_KEY_0, category: KeyCategory.GAMEPLAY, description: '旁观者轮廓' },
];

/**
 * 键码转换工具
 */
export class KeyCodeConverter {
  /** GLFW → AWT 键码映射 */
  static glfwToAWT(glfwCode: number): number {
    const map: Record<number, number> = {
      [GLFWKeyCode.GLFW_KEY_SPACE]: AWTKeyCode.VK_SPACE,
      [GLFWKeyCode.GLFW_KEY_ESCAPE]: AWTKeyCode.VK_ESCAPE,
      [GLFWKeyCode.GLFW_KEY_ENTER]: AWTKeyCode.VK_ENTER,
      [GLFWKeyCode.GLFW_KEY_TAB]: AWTKeyCode.VK_TAB,
      [GLFWKeyCode.GLFW_KEY_LEFT_SHIFT]: AWTKeyCode.VK_SHIFT,
      [GLFWKeyCode.GLFW_KEY_LEFT_CONTROL]: AWTKeyCode.VK_CONTROL,
      [GLFWKeyCode.GLFW_KEY_LEFT_ALT]: AWTKeyCode.VK_ALT,
      [GLFWKeyCode.GLFW_KEY_RIGHT_SHIFT]: AWTKeyCode.VK_SHIFT,
      [GLFWKeyCode.GLFW_KEY_RIGHT_CONTROL]: AWTKeyCode.VK_CONTROL,
      [GLFWKeyCode.GLFW_KEY_BACKSPACE]: AWTKeyCode.VK_BACK_SPACE,
      [GLFWKeyCode.GLFW_KEY_DELETE]: AWTKeyCode.VK_DELETE,
      [GLFWKeyCode.GLFW_KEY_INSERT]: AWTKeyCode.VK_INSERT,
      [GLFWKeyCode.GLFW_KEY_HOME]: AWTKeyCode.VK_HOME,
      [GLFWKeyCode.GLFW_KEY_END]: AWTKeyCode.VK_END,
      [GLFWKeyCode.GLFW_KEY_PAGE_UP]: AWTKeyCode.VK_PAGE_UP,
      [GLFWKeyCode.GLFW_KEY_PAGE_DOWN]: AWTKeyCode.VK_PAGE_DOWN,
      [GLFWKeyCode.GLFW_KEY_LEFT]: AWTKeyCode.VK_LEFT,
      [GLFWKeyCode.GLFW_KEY_UP]: AWTKeyCode.VK_UP,
      [GLFWKeyCode.GLFW_KEY_RIGHT]: AWTKeyCode.VK_RIGHT,
      [GLFWKeyCode.GLFW_KEY_DOWN]: AWTKeyCode.VK_DOWN,
    };

    // 字母键 A-Z: GLFW 65-90 = AWT 65-90
    if (glfwCode >= 65 && glfwCode <= 90) {
      return glfwCode;
    }
    // 数字键 0-9: GLFW 48-57 = AWT 48-57
    if (glfwCode >= 48 && glfwCode <= 57) {
      return glfwCode;
    }
    // F1-F12: GLFW 290-301 = AWT 112-123
    if (glfwCode >= 290 && glfwCode <= 301) {
      return glfwCode - 290 + 112;
    }
    // 小键盘
    if (glfwCode >= 320 && glfwCode <= 329) {
      return glfwCode - 320 + 96;
    }

    return map[glfwCode] ?? glfwCode;
  }

  /** 根据键位名称查找默认 GLFW 键码 */
  static getDefaultKey(bindingName: string): number {
    const binding = MINECRAFT_DEFAULT_BINDINGS.find(b => b.name === bindingName);
    return binding?.defaultKey ?? -1;
  }

  /** 获取所有键位 */
  static getAllBindings(): MinecraftKeyBinding[] {
    return [...MINECRAFT_DEFAULT_BINDINGS];
  }

  /** 按分类获取键位 */
  static getBindingsByCategory(category: KeyCategory): MinecraftKeyBinding[] {
    return MINECRAFT_DEFAULT_BINDINGS.filter(b => b.category === category);
  }

  /** 判断是否为鼠标事件键码 (负数表示鼠标) */
  static isMouseKey(keyCode: number): boolean {
    return keyCode < 0;
  }

  /** 获取鼠标按钮描述 */
  static getMouseButtonDescription(code: number): string {
    switch (code) {
      case -100: return '左键';
      case -99: return '右键';
      case -98: return '中键';
      default: return '鼠标按键';
    }
  }
}
