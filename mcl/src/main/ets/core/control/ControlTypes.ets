/**
 * 触控控件类型定义
 * 移植自: FCL/control/ 中的 ControlButtonStyle / ControlDirectionStyle / ControlTouchpadStyle
 *
 * 独立成文件以避免 TouchController (视图) 与 ControlLayoutStore (存储) 之间的循环依赖。
 */

/** 控件类型 */
export enum ControlType {
  BUTTON = 'button',
  DIRECTION = 'direction',
  TOUCHPAD = 'touchpad',
  KEYBOARD_KEY = 'keyboard_key'
}

/** 按钮配置 */
export interface ButtonConfig {
  id: string;
  type: ControlType;
  /** 键码 (对应 Minecraft 按键) */
  keyCode: number;
  /** 显示文本 */
  label: string;
  /** 位置 (百分比, 0-1) */
  x: number;
  y: number;
  /** 大小 (像素) */
  width: number;
  height: number;
  /** 颜色 */
  color: string;
  /** 透明度 */
  opacity: number;
  /** 是否显示 */
  visible: boolean;
  /** 按下状态 */
  pressed?: boolean;
}

/** 方向键配置 */
export interface DirectionConfig {
  id: string;
  type: ControlType;
  /** 位置 */
  x: number;
  y: number;
  /** 大小 */
  size: number;
  /** 死区 */
  deadZone: number;
  /** 颜色 */
  color: string;
  /** 透明度 */
  opacity: number;
  /** 是否显示 */
  visible: boolean;
  /** 当前方向 */
  currentDirection?: number;
}

/** 触摸板配置 */
export interface TouchpadConfig {
  id: string;
  type: ControlType;
  /** 位置 */
  x: number;
  y: number;
  width: number;
  height: number;
  /** 灵敏度 */
  sensitivity: number;
  /** 透明度 */
  opacity?: number;
  /** 是否显示 */
  visible: boolean;
}

/** 八方向 */
export enum Direction {
  NONE = 0,
  UP = 1,
  DOWN = 2,
  LEFT = 4,
  RIGHT = 8,
  UP_LEFT = 5,
  UP_RIGHT = 9,
  DOWN_LEFT = 6,
  DOWN_RIGHT = 10
}

/** 触控布局配置 (可保存/加载) */
export interface ControlLayout {
  name: string;
  version: number;
  buttons: ButtonConfig[];
  directions: DirectionConfig[];
  touchpads: TouchpadConfig[];
  /** 设备类型 */
  deviceType: 'phone' | 'tablet' | 'pc';
}

/**
 * 默认手机布局
 */
export const DEFAULT_PHONE_LAYOUT: ControlLayout = {
  name: 'Phone Default',
  version: 1,
  deviceType: 'phone',
  buttons: [
    { id: 'btn_shift', type: ControlType.BUTTON, keyCode: 340, label: 'Shift', x: 0.05, y: 0.55, width: 60, height: 40, color: '#FFFFFF', opacity: 0.6, visible: true },
    { id: 'btn_jump', type: ControlType.BUTTON, keyCode: 32, label: 'Jump', x: 0.78, y: 0.75, width: 64, height: 40, color: '#FFFFFF', opacity: 0.6, visible: true },
    { id: 'btn_slot1', type: ControlType.BUTTON, keyCode: 49, label: '1', x: 0.25, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot2', type: ControlType.BUTTON, keyCode: 50, label: '2', x: 0.32, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot3', type: ControlType.BUTTON, keyCode: 51, label: '3', x: 0.39, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot4', type: ControlType.BUTTON, keyCode: 52, label: '4', x: 0.46, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot5', type: ControlType.BUTTON, keyCode: 53, label: '5', x: 0.53, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_inventory', type: ControlType.BUTTON, keyCode: 69, label: 'E', x: 0.88, y: 0.5, width: 40, height: 40, color: '#FFD700', opacity: 0.7, visible: true },
    { id: 'btn_escape', type: ControlType.BUTTON, keyCode: 27, label: 'Esc', x: 0.92, y: 0.05, width: 40, height: 40, color: '#FF5252', opacity: 0.7, visible: true },
    { id: 'btn_chat', type: ControlType.BUTTON, keyCode: 84, label: 'T', x: 0.06, y: 0.92, width: 40, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_f5', type: ControlType.BUTTON, keyCode: 292, label: 'F5', x: 0.92, y: 0.15, width: 40, height: 40, color: '#CCCCCC', opacity: 0.5, visible: true }
  ],
  directions: [
    { id: 'dir_move', type: ControlType.DIRECTION, x: 0.15, y: 0.72, size: 120, deadZone: 20, color: '#FFFFFF', opacity: 0.5, visible: true }
  ],
  touchpads: [
    { id: 'pad_look', type: ControlType.TOUCHPAD, x: 0.55, y: 0.35, width: 0.4, height: 0.5, sensitivity: 1.0, opacity: 0.2, visible: true }
  ]
};
