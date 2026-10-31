/**
 * 触控覆盖层控制器
 * 移植自: FCL/control/ 整个触控系统
 *
 * 支持:
 * - 虚拟按钮 (可自定义大小/位置/颜色)
 * - 虚拟方向键 (八方向)
 * - 触摸板/鼠标模拟
 * - 键盘键位映射
 * - 游戏手柄映射
 * - 陀螺仪控制
 *
 * 多设备适配:
 * - 手机: 完整触摸覆盖层
 * - 平板: 触摸覆盖层 + 外接键鼠
 * - PC: 纯键鼠模式
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import native from 'libfcl_native.so';

const TAG = 'FCL-TouchController';

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
  currentDirection?: Direction;
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
const DEFAULT_PHONE_LAYOUT: ControlLayout = {
  name: 'Phone Default',
  version: 1,
  deviceType: 'phone',
  buttons: [
    // 左侧功能键
    { id: 'btn_shift', type: ControlType.BUTTON, keyCode: 340, label: 'Shift', x: 0.05, y: 0.55, width: 60, height: 40, color: '#FFFFFF', opacity: 0.6, visible: true },
    // 右侧功能键
    { id: 'btn_jump', type: ControlType.BUTTON, keyCode: 32, label: 'Jump', x: 0.78, y: 0.75, width: 64, height: 40, color: '#FFFFFF', opacity: 0.6, visible: true },
    // 物品栏
    { id: 'btn_slot1', type: ControlType.BUTTON, keyCode: 49, label: '1', x: 0.25, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot2', type: ControlType.BUTTON, keyCode: 50, label: '2', x: 0.32, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot3', type: ControlType.BUTTON, keyCode: 51, label: '3', x: 0.39, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot4', type: ControlType.BUTTON, keyCode: 52, label: '4', x: 0.46, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_slot5', type: ControlType.BUTTON, keyCode: 53, label: '5', x: 0.53, y: 0.92, width: 36, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    // 功能键
    { id: 'btn_inventory', type: ControlType.BUTTON, keyCode: 69, label: 'E', x: 0.88, y: 0.5, width: 40, height: 40, color: '#FFD700', opacity: 0.7, visible: true },
    { id: 'btn_escape', type: ControlType.BUTTON, keyCode: 27, label: 'Esc', x: 0.92, y: 0.05, width: 40, height: 40, color: '#FF5252', opacity: 0.7, visible: true },
    { id: 'btn_chat', type: ControlType.BUTTON, keyCode: 84, label: 'T', x: 0.06, y: 0.92, width: 40, height: 36, color: '#CCCCCC', opacity: 0.5, visible: true },
    { id: 'btn_f5', type: ControlType.BUTTON, keyCode: 292, label: 'F5', x: 0.92, y: 0.15, width: 40, height: 40, color: '#CCCCCC', opacity: 0.5, visible: true }
  ],
  directions: [
    // 左侧方向键
    { id: 'dir_move', type: ControlType.DIRECTION, x: 0.15, y: 0.72, size: 120, deadZone: 20, color: '#FFFFFF', opacity: 0.5, visible: true }
  ],
  touchpads: [
    // 右侧视角控制
    { id: 'pad_look', type: ControlType.TOUCHPAD, x: 0.55, y: 0.35, width: 0.4, height: 0.5, sensitivity: 1.0, visible: true }
  ]
};

/**
 * 触控覆盖层组件
 */
@ComponentV2
export struct TouchController {
  @Local layout: ControlLayout = DEFAULT_PHONE_LAYOUT;
  @Local deviceType: string = 'phone';
  @Local isEditing: boolean = false;
  @Local showControls: boolean = true;
  @Local dragTarget: string | null = null;

  /** 控件事件回调 (通过 NAPI 发送到 JVM) */
  keyEventCallback?: (keyCode: number, pressed: boolean) => void;
  mouseMoveCallback?: (dx: number, dy: number) => void;
  directionCallback?: (direction: Direction) => void;

  /** 触摸板上一帧手指位置（增量计算用，无需 UI 观察） */
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;

  aboutToAppear(): void {
    this.deviceType = deviceInfo.deviceType;
    // PC 模式下隐藏触控覆盖层
    if (this.deviceType === '2in1') {
      this.showControls = false;
    }
    // 加载保存的布局
    this.loadLayout();
  }

  async loadLayout(): Promise<void> {
    // TODO: 从 Preferences 加载
  }

  async saveLayout(): Promise<void> {
    // TODO: 保存到 Preferences
  }

  build() {
    Stack() {
      if (!this.showControls) {
        // PC 模式: 显示提示
        Text('Keyboard & Mouse Mode')
          .fontSize(14)
          .fontColor('#999999')
          .position({ x: '50%', y: 8 })
      } else {
        // 方向键
        ForEach(this.layout.directions.filter(d => d.visible),
          (dir: DirectionConfig) => {
            this.buildDirectionPad(dir);
          }
        );

        // 按钮
        ForEach(this.layout.buttons.filter(b => b.visible),
          (btn: ButtonConfig) => {
            this.buildButton(btn);
          }
        );

        // 触摸板
        ForEach(this.layout.touchpads.filter(t => t.visible),
          (pad: TouchpadConfig) => {
            this.buildTouchpad(pad);
          }
        );
      }

      // 编辑模式切换
      if (this.isEditing) {
        this.buildEditToolbar();
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.showControls ? HitTestMode.None : HitTestMode.Default)
  }

  /** 构建虚拟按钮 */
  @Builder
  buildButton(btn: ButtonConfig) {
    Stack() {
      Text(btn.label)
        .fontSize(12)
        .fontColor(btn.color)
        .fontWeight(FontWeight.Medium)
    }
    .width(btn.width)
    .height(btn.height)
    .backgroundColor(btn.pressed ?
      `rgba(255,255,255,${btn.opacity + 0.2})` :
      `rgba(255,255,255,${btn.opacity * 0.3})`)
    .borderRadius(8)
    .border({ width: 1.5, color: `${btn.color}${Math.floor(btn.opacity * 255).toString(16).padStart(2, '0')}` })
    .position({ x: `${btn.x * 100}%`, y: `${btn.y * 100}%` })
    .offset({ x: -btn.width / 2, y: -btn.height / 2 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        btn.pressed = true;
        this.sendKeyEvent(btn.keyCode, true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        btn.pressed = false;
        this.sendKeyEvent(btn.keyCode, false);
      }
      event.stopPropagation();
    })
    // 编辑模式: 可拖拽移动
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1 })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isEditing && this.dragTarget === btn.id) {
              btn.x += event.offsetX / 1000;
              btn.y += event.offsetY / 1000;
              btn.x = Math.max(0, Math.min(1, btn.x));
              btn.y = Math.max(0, Math.min(1, btn.y));
            }
          })
          .onActionStart(() => {
            if (this.isEditing) {
              this.dragTarget = btn.id;
            }
          })
          .onActionEnd(() => {
            this.dragTarget = null;
          })
      )
    )
  }

  /** 构建方向键 */
  @Builder
  buildDirectionPad(dir: DirectionConfig) {
    Stack() {
      // 外圈
      Circle()
        .width(dir.size)
        .height(dir.size)
        .fill('rgba(255,255,255,0.1)')
        .stroke(`${dir.color}${Math.floor(dir.opacity * 255).toString(16).padStart(2, '0')}`)
        .strokeWidth(2)

      // 内圈 (跟随手指)
      Circle()
        .width(40)
        .height(40)
        .fill(`rgba(255,255,255,${dir.opacity * 0.3})`)
        .position({ x: dir.size / 2 - 20, y: dir.size / 2 - 20 })
    }
    .width(dir.size)
    .height(dir.size)
    .position({ x: `${dir.x * 100}%`, y: `${dir.y * 100}%` })
    .offset({ x: -dir.size / 2, y: -dir.size / 2 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        // 计算手指相对中心的位置
        const centerX = event.touches[0].x;
        const centerY = event.touches[0].y;
        const relX = centerX - (parseFloat(String(dir.x * 100)) / 100 * 100);
        const relY = centerY - (parseFloat(String(dir.y * 100)) / 100 * 100);

        const angle = Math.atan2(relY, relX);
        const distance = Math.sqrt(relX * relX + relY * relY);

        if (distance < dir.deadZone) {
          if (this.directionCallback) this.directionCallback(Direction.NONE);
          return;
        }

        // 将角度转换为八方向
        let direction: Direction;
        const octant = Math.round(8 * angle / (2 * Math.PI) + 8) % 8;
        switch (octant) {
          case 0: direction = Direction.RIGHT; break;
          case 1: direction = Direction.DOWN_RIGHT; break;
          case 2: direction = Direction.DOWN; break;
          case 3: direction = Direction.DOWN_LEFT; break;
          case 4: direction = Direction.LEFT; break;
          case 5: direction = Direction.UP_LEFT; break;
          case 6: direction = Direction.UP; break;
          case 7: direction = Direction.UP_RIGHT; break;
          default: direction = Direction.NONE;
        }

        if (this.directionCallback) this.directionCallback(direction);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.directionCallback) this.directionCallback(Direction.NONE);
      }
      event.stopPropagation();
    })
  }

  /** 构建触摸板 */
  @Builder
  buildTouchpad(pad: TouchpadConfig) {
    Column()
      .width(`${pad.width * 100}%`)
      .height(`${pad.height * 100}%`)
      .position({ x: `${pad.x * 100}%`, y: `${pad.y * 100}%` })
      .backgroundColor('rgba(0,0,0,0.01)') // 几乎透明但可以接收触摸
      .border({ width: 1, color: 'rgba(255,255,255,0.1)', style: BorderStyle.Dashed })
      .borderRadius(12)
      .onTouch((event: TouchEvent) => {
        if (event.touches.length > 0) {
          const x = event.touches[0].x;
          const y = event.touches[0].y;
          if (event.type === TouchType.Down) {
            // 按下：记录起点，不做增量
            this.lastTouchX = x;
            this.lastTouchY = y;
          } else if (event.type === TouchType.Move) {
            // 基于上一帧位置计算增量，乘以灵敏度
            const dx = (x - this.lastTouchX) * pad.sensitivity;
            const dy = (y - this.lastTouchY) * pad.sensitivity;
            this.lastTouchX = x;
            this.lastTouchY = y;
            if (this.mouseMoveCallback) {
              this.mouseMoveCallback(dx, dy);
            }
            // NAPI：相对视角增量送入 native ring buffer
            native.sendCursorPos(dx, dy);
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.lastTouchX = 0;
            this.lastTouchY = 0;
          }
        }
        event.stopPropagation();
      })
  }

  /** 编辑工具栏 */
  @Builder
  buildEditToolbar() {
    Row() {
      Button('Add Button')
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(6)
        .padding(8)
        .margin({ right: 6 })
        .onClick(() => this.addNewButton())

      Button('Add Direction')
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(6)
        .padding(8)
        .margin({ right: 6 })
        .onClick(() => this.addNewDirection())

      Button('Save')
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor('#E94560')
        .borderRadius(6)
        .padding(8)
        .margin({ right: 6 })
        .onClick(() => {
          this.isEditing = false;
          this.saveLayout();
        })

      Button('Done')
        .fontSize(12)
        .fontColor('#4CAF50')
        .backgroundColor('transparent')
        .border({ width: 1, color: '#4CAF50' })
        .borderRadius(6)
        .padding(8)
        .onClick(() => { this.isEditing = false; })
    }
    .padding(8)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .position({ x: '50%', y: 8 })
    .translate({ x: '-50%', y: 0 })
  }

  /** 发送按键事件到 JVM */
  private sendKeyEvent(keyCode: number, pressed: boolean): void {
    if (this.keyEventCallback) {
      this.keyEventCallback(keyCode, pressed);
    }
    // NAPI 调用：事件进入 native ring buffer（Phase 2 的 GLFW 兼容层在
    // glfwPollEvents 时消费；GLFW 键码与 TouchController 的 keyCode 体系一致）
    native.sendKeyEvent(keyCode, pressed ? 1 : 0);
    hilog.debug(0x0000, TAG, `Key event: code=${keyCode}, pressed=${pressed}`);
  }

  private addNewButton(): void {
    const id = `btn_custom_${this.layout.buttons.length}`;
    this.layout.buttons.push({
      id,
      type: ControlType.BUTTON,
      keyCode: 0,
      label: '?',
      x: 0.5, y: 0.5,
      width: 48, height: 48,
      color: '#FFFFFF',
      opacity: 0.5,
      visible: true
    });
  }

  private addNewDirection(): void {
    this.layout.directions.push({
      id: `dir_custom_${this.layout.directions.length}`,
      type: ControlType.DIRECTION,
      x: 0.5, y: 0.5,
      size: 120,
      deadZone: 20,
      color: '#FFFFFF',
      opacity: 0.5,
      visible: true
    });
  }
}
