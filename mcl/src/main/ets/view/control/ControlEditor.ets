/**
 * 自定义控件布局编辑器
 * 移植自: FCL/control/ 中的 EditViewDialog + ControlButtonStyle + ControlDirectionStyle
 *
 * 功能: 拖拽调整位置、大小、颜色、透明度，新增/删除控件
 */
import { ControlLayout, ButtonConfig, DirectionConfig, TouchpadConfig,
  ControlType, Direction } from './TouchController';
import { FileUtils } from '../../core/util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { promptAction } from '@kit.ArkUI';

const LAYOUT_FILE = 'fcl_control_layout.json';

/** 控件模板 */
interface ControlTemplate {
  label: string;
  keyCode: number;
  type: ControlType;
}

/** 预置按钮模板 */
const BUTTON_TEMPLATES: ControlTemplate[] = [
  { label: 'W/S/A/D', keyCode: 0, type: ControlType.BUTTON },
  { label: 'Jump (Space)', keyCode: 32, type: ControlType.BUTTON },
  { label: 'Shift', keyCode: 340, type: ControlType.BUTTON },
  { label: 'Inventory (E)', keyCode: 69, type: ControlType.BUTTON },
  { label: 'Attack (LClick)', keyCode: 1000, type: ControlType.BUTTON },
  { label: 'Use (RClick)', keyCode: 1001, type: ControlType.BUTTON },
  { label: 'Chat (T)', keyCode: 84, type: ControlType.BUTTON },
  { label: 'Sneak (Ctrl)', keyCode: 341, type: ControlType.BUTTON },
  { label: 'Sprint', keyCode: 342, type: ControlType.BUTTON },
  { label: 'Drop (Q)', keyCode: 81, type: ControlType.BUTTON },
  { label: 'F3 Debug', keyCode: 292, type: ControlType.BUTTON },
  { label: 'ESC', keyCode: 27, type: ControlType.BUTTON },
  { label: 'Hotbar 1', keyCode: 49, type: ControlType.BUTTON },
  { label: 'Hotbar 2', keyCode: 50, type: ControlType.BUTTON },
  { label: 'Hotbar 3', keyCode: 51, type: ControlType.BUTTON },
  { label: 'Hotbar 4', keyCode: 52, type: ControlType.BUTTON },
  { label: 'Hotbar 5', keyCode: 53, type: ControlType.BUTTON },
  { label: 'Hotbar 6', keyCode: 54, type: ControlType.BUTTON },
  { label: 'Hotbar 7', keyCode: 55, type: ControlType.BUTTON },
  { label: 'Hotbar 8', keyCode: 56, type: ControlType.BUTTON },
  { label: 'Hotbar 9', keyCode: 57, type: ControlType.BUTTON },
  { label: 'Perspective (F5)', keyCode: 292, type: ControlType.BUTTON },
  { label: 'Screenshot (F2)', keyCode: 291, type: ControlType.BUTTON },
  { label: 'Fullscreen (F11)', keyCode: 293, type: ControlType.BUTTON }
];

@ComponentV2
export struct ControlEditor {
  @Local layout: ControlLayout = {
    name: 'Custom Layout',
    version: 1,
    deviceType: 'phone',
    buttons: [],
    directions: [],
    touchpads: []
  };

  @Local selectedId: string = '';
  @Local showAddDialog: boolean = false;
  @Local showPropertyEditor: boolean = false;
  @Local editProperty: 'color' | 'opacity' | 'size' | 'keycode' = 'color';
  @Local layoutName: string = '';
  @Local savedLayouts: string[] = [];

  aboutToAppear(): void {
    this.loadLayout();
    this.loadLayoutList();
  }

  loadLayout(): void {
    const path = `${AppContext.filesDir}/${LAYOUT_FILE}`;
    const saved = FileUtils.readJSON<ControlLayout>(path);
    if (saved) {
      this.layout = saved;
      this.layoutName = saved.name;
    } else {
      // 默认布局
      this.layout = {
        name: 'Default',
        version: 1,
        deviceType: 'phone',
        buttons: [
          { id: 'btn_move', type: ControlType.BUTTON, keyCode: 87, label: 'W', x: 0.5, y: 0.85, width: 48, height: 48, color: '#FFFFFF', opacity: 0.6, visible: true },
          { id: 'btn_jump', type: ControlType.BUTTON, keyCode: 32, label: 'Jump', x: 0.8, y: 0.78, width: 64, height: 48, color: '#FFFFFF', opacity: 0.6, visible: true }
        ],
        directions: [
          { id: 'dir_move', type: ControlType.DIRECTION, x: 0.15, y: 0.72, size: 130, deadZone: 20, color: '#FFFFFF', opacity: 0.5, visible: true }
        ],
        touchpads: [
          { id: 'pad_look', type: ControlType.TOUCHPAD, x: 0.55, y: 0.3, width: 0.45, height: 0.55, sensitivity: 1.0, visible: true }
        ]
      };
      this.layoutName = this.layout.name;
    }
  }

  loadLayoutList(): void {
    const dir = AppContext.filesDir;
    const files = FileUtils.listFiles(dir)
      .filter(f => f.startsWith('fcl_control_layout_') && f.endsWith('.json'));
    this.savedLayouts = files.map(f => f.replace('fcl_control_layout_', '').replace('.json', ''));
  }

  saveLayout(): void {
    this.layout.name = this.layoutName;
    const path = `${AppContext.filesDir}/${LAYOUT_FILE}`;
    FileUtils.writeJSON(path, this.layout);
    promptAction.showToast({ message: 'Layout saved' });
  }

  build() {
    Stack() {
      Column() {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor('#1A1A1A')

          ForEach(this.layout.buttons.filter(b => b.visible), (btn: ButtonConfig) => {
            this.buildEditableButton(btn);
          });

          ForEach(this.layout.directions.filter(d => d.visible), (dir: DirectionConfig) => {
            this.buildEditableDirection(dir);
          });

          ForEach(this.layout.touchpads.filter(t => t.visible), (pad: TouchpadConfig) => {
            this.buildEditableTouchpad(pad);
          });
        }
        .width('100%').layoutWeight(1)
        .border({ width: 2, color: '#E94560', style: BorderStyle.Dashed })
      }
      .width('100%').layoutWeight(1)

      this.buildEditorToolbar();

      if (this.showAddDialog) {
        this.buildAddControlDialog();
      }
    }
    .width('100%').height('100%').backgroundColor('#1A1A2E')
  }

  @Builder
  buildEditableButton(btn: ButtonConfig) {
    Stack() {
      Text(btn.label)
        .fontSize(11).fontColor(btn.color)
        .fontWeight(FontWeight.Medium)
    }
    .width(btn.width).height(btn.height)
    .backgroundColor(btn.id === this.selectedId ?
      'rgba(233,69,96,0.3)' : `rgba(255,255,255,${btn.opacity * 0.3})`)
    .borderRadius(8)
    .border({
      width: btn.id === this.selectedId ? 2 : 1,
      color: btn.id === this.selectedId ? '#E94560' :
        `${btn.color}${Math.floor(btn.opacity * 255).toString(16).padStart(2, '0')}`
    })
    .position({ x: `${btn.x * 100}%`, y: `${btn.y * 100}%` })
    .offset({ x: -btn.width / 2, y: -btn.height / 2 })
    .onClick(() => { this.selectedId = btn.id; })
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionUpdate((event: GestureEvent) => {
          if (this.selectedId === btn.id) {
            btn.x += event.offsetX / 1000;
            btn.y += event.offsetY / 1000;
            btn.x = Math.max(0, Math.min(1, btn.x));
            btn.y = Math.max(0, Math.min(1, btn.y));
          }
        })
    )
  }

  @Builder
  buildEditableDirection(dir: DirectionConfig) {
    Stack() {
      Circle()
        .width(dir.size).height(dir.size)
        .fill('rgba(255,255,255,0.08)')
        .stroke({
          width: dir.id === this.selectedId ? 2.5 : 1.5,
          color: dir.id === this.selectedId ? '#E94560' : `${dir.color}80`
        })
    }
    .width(dir.size).height(dir.size)
    .position({ x: `${dir.x * 100}%`, y: `${dir.y * 100}%` })
    .offset({ x: -dir.size / 2, y: -dir.size / 2 })
    .onClick(() => { this.selectedId = dir.id; })
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionUpdate((event: GestureEvent) => {
          if (this.selectedId === dir.id) {
            dir.x += event.offsetX / 1000;
            dir.y += event.offsetY / 1000;
            dir.x = Math.max(0, Math.min(1, dir.x));
            dir.y = Math.max(0, Math.min(1, dir.y));
          }
        })
    )
  }

  @Builder
  buildEditableTouchpad(pad: TouchpadConfig) {
    Column()
      .width(`${pad.width * 100}%`).height(`${pad.height * 100}%`)
      .position({ x: `${pad.x * 100}%`, y: `${pad.y * 100}%` })
      .backgroundColor('rgba(255,255,255,0.02)')
      .border({
        width: pad.id === this.selectedId ? 2 : 1,
        color: pad.id === this.selectedId ? '#E94560' : 'rgba(255,255,255,0.15)',
        style: BorderStyle.Dashed
      })
      .borderRadius(8)
      .onClick(() => { this.selectedId = pad.id; })
  }

  @Builder
  buildEditorToolbar() {
    Column() {
      // 属性编辑区
      if (this.selectedId) {
        this.buildPropertyControls();
      }

      // 操作按钮
      Row() {
        this.buildToolBtn('Add Button', () => { this.showAddDialog = true; })
        this.buildToolBtn('Add Dir', () => { this.addDirection(); })
        this.buildToolBtn('Add Pad', () => { this.addTouchpad(); })

        if (this.selectedId) {
          this.buildToolBtn('Delete', () => { this.deleteSelected(); })
          this.buildToolBtn('Hide', () => { this.toggleVisibility(); })
        }

        this.buildToolBtn('Save', () => { this.saveLayout(); })
        this.buildToolBtn('Reset', () => { this.loadLayout(); })
      }
      .width('100%').padding(8)
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('100%').backgroundColor('#16213E')
  }

  @Builder
  buildPropertyControls() {
    Column() {
      Text('Selected: ' + this.selectedId)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .margin({ bottom: 8 })

      // 透明度滑块
      Row() {
        Text('Opacity').fontSize(12).fontColor('#999999').width(60)
        Slider({ value: 0.5, min: 0.1, max: 1, step: 0.05, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.updateSelected('opacity', value);
          })
      }
      .width('100%').margin({ bottom: 4 })

      // 大小滑块
      Row() {
        Text('Size').fontSize(12).fontColor('#999999').width(60)
        Slider({ value: 48, min: 24, max: 200, step: 2, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.updateSelected('size', value);
          })
      }
      .width('100%')

      // 颜色选择器
      Row() {
        Text('Color').fontSize(12).fontColor('#999999').width(60)
        ForEach(['#FFFFFF', '#FF5252', '#4CAF50', '#2196F3', '#FFD700', '#FF9800', '#E94560', '#9C27B0'],
          (color: string) => {
            Circle({ width: 24, height: 24 })
              .fill(color)
              .margin({ right: 4 })
              .onClick(() => { this.updateSelected('color', color); })
          }
        )
      }
      .width('100%')
    }
    .width('100%').padding(12)
  }

  @Builder
  buildToolBtn(label: string, action: () => void) {
    Button(label)
      .fontSize(11).fontColor('#FFFFFF')
      .backgroundColor('#0F3460').borderRadius(6)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .onClick(action)
  }

  @Builder
  buildAddControlDialog() {
    Column() {
      Column() {
        Text('Add Control').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').margin({ bottom: 12 })

        Scroll() {
          Column() {
            ForEach(BUTTON_TEMPLATES, (template: ControlTemplate) => {
              Row() {
                Text(template.label).fontSize(14).fontColor('#FFFFFF').layoutWeight(1)
                Button('Add').fontSize(12).fontColor('#FFFFFF')
                  .backgroundColor('#E94560').borderRadius(6)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.addButton(template);
                    this.showAddDialog = false;
                  })
              }
              .width('100%').padding(8)
              .margin({ bottom: 4 })
            })
          }
        }
        .height(400)

        Button('Close').fontSize(14).fontColor('#999999')
          .backgroundColor('transparent').margin({ top: 8 })
          .onClick(() => { this.showAddDialog = false; })
      }
      .padding(20).backgroundColor('#16213E').borderRadius(16).width('85%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showAddDialog = false; })
  }

  // ========== 操作 ==========

  addButton(template: ControlTemplate): void {
    const id = `btn_${this.layout.buttons.length}_${Date.now()}`;
    this.layout.buttons.push({
      id, type: ControlType.BUTTON,
      keyCode: template.keyCode, label: template.label,
      x: 0.5, y: 0.5, width: 48, height: 48,
      color: '#FFFFFF', opacity: 0.6, visible: true
    });
    this.selectedId = id;
  }

  addDirection(): void {
    const id = `dir_${this.layout.directions.length}`;
    this.layout.directions.push({
      id, type: ControlType.DIRECTION,
      x: 0.3, y: 0.5, size: 120, deadZone: 15,
      color: '#FFFFFF', opacity: 0.5, visible: true
    });
    this.selectedId = id;
  }

  addTouchpad(): void {
    const id = `pad_${this.layout.touchpads.length}`;
    this.layout.touchpads.push({
      id, type: ControlType.TOUCHPAD,
      x: 0.5, y: 0.3, width: 0.4, height: 0.5,
      sensitivity: 1.0, visible: true
    });
    this.selectedId = id;
  }

  deleteSelected(): void {
    this.layout.buttons = this.layout.buttons.filter(b => b.id !== this.selectedId);
    this.layout.directions = this.layout.directions.filter(d => d.id !== this.selectedId);
    this.layout.touchpads = this.layout.touchpads.filter(t => t.id !== this.selectedId);
    this.selectedId = '';
  }

  toggleVisibility(): void {
    for (const btn of this.layout.buttons) {
      if (btn.id === this.selectedId) { btn.visible = !btn.visible; return; }
    }
    for (const dir of this.layout.directions) {
      if (dir.id === this.selectedId) { dir.visible = !dir.visible; return; }
    }
    for (const pad of this.layout.touchpads) {
      if (pad.id === this.selectedId) { pad.visible = !pad.visible; return; }
    }
  }

  updateSelected(prop: string, value: string | number): void {
    for (const btn of this.layout.buttons) {
      if (btn.id === this.selectedId) {
        if (prop === 'color' && typeof value === 'string') btn.color = value;
        if (prop === 'opacity' && typeof value === 'number') btn.opacity = value;
        if (prop === 'size' && typeof value === 'number') { btn.width = value; btn.height = value * 0.8; }
        return;
      }
    }
    for (const dir of this.layout.directions) {
      if (dir.id === this.selectedId) {
        if (prop === 'color' && typeof value === 'string') dir.color = value;
        if (prop === 'opacity' && typeof value === 'number') dir.opacity = value;
        if (prop === 'size' && typeof value === 'number') dir.size = value;
        return;
      }
    }
  }
}
