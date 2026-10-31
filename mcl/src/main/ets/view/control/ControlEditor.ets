/**
 * 自定义控件布局编辑器
 * 移植自: FCL/control/ 中的 EditViewDialog + ControlButtonStyle + ControlDirectionStyle
 *
 * 功能:
 * - 拖拽调整位置、大小、颜色、透明度, 新增/删除控件
 * - 多布局管理: 切换 / 复制 / 重命名 / 删除 (对应上游 FCL 的布局切换功能)
 * - 与游戏内触控覆盖层共用 ControlLayoutStore, 保存后立即生效
 */
import { ControlType, ButtonConfig, DirectionConfig, TouchpadConfig,
  ControlLayout, DEFAULT_PHONE_LAYOUT } from '../../core/control/ControlTypes';
import { ControlLayoutStore, LayoutEntry } from '../../core/control/ControlLayoutStore';
import { promptAction } from '@kit.ArkUI';

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
  @Local showLayoutDialog: boolean = false;
  @Local layoutName: string = '';
  @Local savedLayouts: LayoutEntry[] = [];
  @Local currentLayoutId: string = '';
  @Local showRenameLayoutDialog: boolean = false;
  @Local renameLayoutInput: string = '';

  aboutToAppear(): void {
    this.loadLayout();
    this.loadLayoutList();
  }

  loadLayout(): void {
    const saved = ControlLayoutStore.loadCurrent();
    if (saved) {
      this.layout = saved;
      this.layoutName = saved.name;
      this.currentLayoutId = ControlLayoutStore.sanitizeId(saved.name);
    } else {
      this.layout = DEFAULT_PHONE_LAYOUT;
      this.layoutName = this.layout.name;
      this.currentLayoutId = ControlLayoutStore.sanitizeId(this.layout.name);
    }
  }

  loadLayoutList(): void {
    this.savedLayouts = ControlLayoutStore.listLayouts();
  }

  saveLayout(): void {
    this.layout.name = this.layoutName;
    if (ControlLayoutStore.saveCurrent(this.layout)) {
      this.currentLayoutId = ControlLayoutStore.sanitizeId(this.layout.name);
      this.loadLayoutList();
      promptAction.showToast({ message: 'Layout saved' });
    } else {
      promptAction.showToast({ message: 'Failed to save layout' });
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部: 布局选择器
        this.buildLayoutBar();

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
      if (this.showLayoutDialog) {
        this.buildLayoutManagerDialog();
      }
      if (this.showRenameLayoutDialog) {
        this.buildRenameLayoutDialog();
      }
    }
    .width('100%').height('100%').backgroundColor('#1A1A2E')
  }

  /** 顶部布局选择条 */
  @Builder
  buildLayoutBar() {
    Row() {
      Text(`Layout: ${this.layoutName}`)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .layoutWeight(1)

      Button('Layouts')
        .fontSize(12).fontColor('#FFFFFF').backgroundColor('#0F3460')
        .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.loadLayoutList();
          this.showLayoutDialog = true;
        })
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#16213E')
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
        .stroke(dir.id === this.selectedId ? '#E94560' : `${dir.color}80`)
        .strokeWidth(dir.id === this.selectedId ? 2.5 : 1.5)
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

  /**
   * 属性控制区
   * 滑块初值取自当前选中控件的真实属性 (此前硬编码为固定值, 导致调整无效)
   */
  @Builder
  buildPropertyControls() {
    Column() {
      Text('Selected: ' + this.selectedId)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .margin({ bottom: 8 })

      // 透明度滑块
      Row() {
        Text('Opacity').fontSize(12).fontColor('#999999').width(60)
        Slider({ value: this.currentOpacity(), min: 0.1, max: 1, step: 0.05, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.updateSelected('opacity', value);
          })
      }
      .width('100%').margin({ bottom: 4 })

      // 大小滑块
      Row() {
        Text('Size').fontSize(12).fontColor('#999999').width(60)
        Slider({ value: this.currentSize(), min: 24, max: 200, step: 2, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.updateSelected('size', value);
          })
      }
      .width('100%')

      // 触摸板灵敏度 (仅触摸板可调)
      if (this.isTouchpadSelected()) {
        Row() {
          Text('Sensitivity').fontSize(12).fontColor('#999999').width(60)
          Slider({ value: this.currentSensitivity(), min: 0.1, max: 5, step: 0.1, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.updateSelected('sensitivity', value);
            })
        }
        .width('100%').margin({ top: 4 })
      }

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

  /** 布局管理对话框 */
  @Builder
  buildLayoutManagerDialog() {
    Column() {
      Column() {
        Text('Control Layouts').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').margin({ bottom: 12 })

        Scroll() {
          Column() {
            ForEach(this.savedLayouts, (entry: LayoutEntry) => {
              Row() {
                Text(entry.id === this.currentLayoutId ? `★ ${entry.name}` : entry.name)
                  .fontSize(14)
                  .fontColor(entry.id === this.currentLayoutId ? '#E94560' : '#FFFFFF')
                  .layoutWeight(1)

                Button('Use').fontSize(11).fontColor('#FFFFFF').backgroundColor('#4CAF50')
                  .borderRadius(6).padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .margin({ right: 6 })
                  .onClick(() => { this.switchLayout(entry.id); })

                Button('Rename').fontSize(11).fontColor('#FFFFFF').backgroundColor('#0F3460')
                  .borderRadius(6).padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .margin({ right: 6 })
                  .onClick(() => {
                    this.renameLayoutInput = entry.name;
                    this.showRenameLayoutDialog = true;
                  })

                Button('Delete').fontSize(11).fontColor('#FF5252').backgroundColor('rgba(255,82,82,0.15)')
                  .borderRadius(6).padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .onClick(() => { this.deleteLayout(entry.id); })
              }
              .width('100%').padding(8)
              .margin({ bottom: 6 })
              .backgroundColor('#0F3460').borderRadius(6)
            })
          }
        }
        .height(320)

        // 新建 (复制当前布局)
        TextInput({ placeholder: 'New layout name', text: this.layoutName })
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(6).padding(10).width('100%').margin({ top: 8 })
          .onChange((v: string) => { this.layoutName = v; })

        Button('Duplicate Current')
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#E94560')
          .borderRadius(6).padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ top: 8 })
          .onClick(() => { this.duplicateLayout(); })

        Button('Close').fontSize(13).fontColor('#999999')
          .backgroundColor('transparent').margin({ top: 6 })
          .onClick(() => { this.showLayoutDialog = false; })
      }
      .padding(20).backgroundColor('#16213E').borderRadius(16).width('88%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showLayoutDialog = false; })
  }

  @Builder
  buildRenameLayoutDialog() {
    Column() {
      Column() {
        Text('Rename Layout').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').margin({ bottom: 12 })
        TextInput({ placeholder: 'Layout name', text: this.renameLayoutInput })
          .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(8).padding(12).width('100%').margin({ bottom: 16 })
          .onChange((v: string) => { this.renameLayoutInput = v; })
        Row() {
          Button('Cancel').fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => { this.showRenameLayoutDialog = false; })
          Button('Rename').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 20, right: 20, top: 10, bottom: 10 }).margin({ left: 16 })
            .onClick(() => {
              this.renameLayout(this.renameLayoutInput);
              this.showRenameLayoutDialog = false;
            })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('80%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showRenameLayoutDialog = false; })
  }

  // ========== 布局操作 ==========

  switchLayout(id: string): void {
    if (ControlLayoutStore.switchTo(id)) {
      this.loadLayout();
      this.loadLayoutList();
      promptAction.showToast({ message: `Switched to layout: ${this.layoutName}` });
    } else {
      promptAction.showToast({ message: 'Failed to switch layout' });
    }
  }

  duplicateLayout(): void {
    if (this.layoutName.trim().length === 0) {
      promptAction.showToast({ message: 'Enter a name first' });
      return;
    }
    // 先把当前编辑内容保存, 再复制
    this.layout.name = this.layoutName;
    ControlLayoutStore.saveCurrent(this.layout);
    if (ControlLayoutStore.duplicate(this.layout.name, this.layoutName)) {
      this.loadLayoutList();
      promptAction.showToast({ message: `Duplicated to: ${this.layoutName}` });
    } else {
      promptAction.showToast({ message: 'Failed to duplicate layout' });
    }
  }

  renameLayout(newName: string): void {
    if (newName.trim().length === 0) {
      return;
    }
    if (ControlLayoutStore.rename(this.currentLayoutId, newName)) {
      this.layout.name = newName;
      this.layoutName = newName;
      this.currentLayoutId = ControlLayoutStore.sanitizeId(newName);
      this.loadLayoutList();
      promptAction.showToast({ message: `Renamed to: ${newName}` });
    } else {
      promptAction.showToast({ message: 'Failed to rename layout' });
    }
  }

  deleteLayout(id: string): void {
    ControlLayoutStore.remove(id);
    this.loadLayoutList();
    if (this.currentLayoutId === id) {
      this.loadLayout();
    }
    promptAction.showToast({ message: 'Layout deleted' });
  }

  // ========== 控件操作 ==========

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
      sensitivity: 1.0, opacity: 0.2, visible: true
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

  /** 读取当前选中控件的透明度 (无选中时返回默认值) */
  private currentOpacity(): number {
    for (const btn of this.layout.buttons) {
      if (btn.id === this.selectedId) { return btn.opacity; }
    }
    for (const dir of this.layout.directions) {
      if (dir.id === this.selectedId) { return dir.opacity; }
    }
    for (const pad of this.layout.touchpads) {
      if (pad.id === this.selectedId) { return pad.opacity ?? 0.2; }
    }
    return 0.5;
  }

  /** 读取当前选中控件的尺寸 */
  private currentSize(): number {
    for (const btn of this.layout.buttons) {
      if (btn.id === this.selectedId) { return btn.width; }
    }
    for (const dir of this.layout.directions) {
      if (dir.id === this.selectedId) { return dir.size; }
    }
    return 48;
  }

  /** 读取当前选中触摸板的灵敏度 */
  private currentSensitivity(): number {
    for (const pad of this.layout.touchpads) {
      if (pad.id === this.selectedId) { return pad.sensitivity; }
    }
    return 1.0;
  }

  /** 当前选中的是否为触摸板 */
  private isTouchpadSelected(): boolean {
    for (const pad of this.layout.touchpads) {
      if (pad.id === this.selectedId) { return true; }
    }
    return false;
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
    for (const pad of this.layout.touchpads) {
      if (pad.id === this.selectedId) {
        if (prop === 'opacity' && typeof value === 'number') pad.opacity = value;
        if (prop === 'sensitivity' && typeof value === 'number') pad.sensitivity = value;
        return;
      }
    }
  }
}
