/**
 * FCL 主入口页面
 * 使用 Navigation + NavPathStack 管理全部页面路由
 * 多设备: 手机底部Tab / 平板PC侧边栏
 */
import { display } from '@kit.ArkUI';
import { MainPage } from '../view/main/MainPage';
import { SettingsPage } from '../view/setting/SettingsPage';
import { AccountPage } from '../view/account/AccountPage';
import { DownloadPage } from '../view/download/DownloadPage';
import { ManagePage } from '../view/manage/ManagePage';
import { MultiplayerPage } from '../view/multiplayer/MultiplayerPage';
import { VersionDetailPage } from '../view/version/VersionDetailPage';
import { ControlEditor } from '../view/control/ControlEditor';
import { GameLogViewer } from '../view/common/GameLogViewer';
import { CrashReportView } from '../view/common/CrashReporter';
import { GamePage } from '../view/game/GamePage';
import { RendererPage } from '../view/setting/RendererPage';
import { MgOptionsPage } from '../view/setting/MgOptionsPage';
import { NavigationService, RouteNames } from '../common/NavigationRouter';
import { AppVersion } from '../core/util/AppVersion';

@Entry
@ComponentV2
struct Index {
  @Local navPathStack: NavPathStack = new NavPathStack();
  @Local currentBreakpoint: string = 'sm';
  @Local selectedTabIndex: number = 0;

  aboutToAppear(): void {
    NavigationService.init(this.navPathStack);

    const displayInfo = display.getDefaultDisplaySync();
    this.updateBreakpoint(displayInfo.width);
    display.on('change', (displayId: number) => {
      const info = display.getDefaultDisplaySync();
      this.updateBreakpoint(info.width);
    });
  }

  private updateBreakpoint(width: number): void {
    if (width < 320) {
      this.currentBreakpoint = 'xs';
    } else if (width < 600) {
      this.currentBreakpoint = 'sm';
    } else if (width < 840) {
      this.currentBreakpoint = 'md';
    } else if (width < 1440) {
      this.currentBreakpoint = 'lg';
    } else {
      this.currentBreakpoint = 'xl';
    }
  }

  private selectTab(index: number): void {
    this.selectedTabIndex = index;
  }

  /** 点击版本卡片 → 推入详情页 */
  private openVersionDetail(versionId: string): void {
    NavigationService.push(RouteNames.VERSION_DETAIL, { versionId } as ESObject);
  }

  build() {
    Navigation(this.navPathStack) {
      if (this.currentBreakpoint === 'lg' || this.currentBreakpoint === 'xl') {
        this.buildWideLayout();
      } else {
        this.buildNarrowLayout();
      }
    }
    .navDestination(this.routeMap)
    .mode(NavigationMode.Auto)
    .hideTitleBar(true)
  }

  @Builder
  routeMap(name: string, param: ESObject) {
    if (name === RouteNames.VERSION_DETAIL) {
      VersionDetailPage({ versionId: (param as Record<string, string>)?.['versionId'] ?? '' })
    } else if (name === RouteNames.GAME_LOG) {
      GameLogViewer()
    } else if (name === RouteNames.CRASH_REPORT) {
      CrashReportView()
    } else if (name === RouteNames.CONTROL_EDITOR) {
      ControlEditor()
    } else if (name === RouteNames.GAME) {
      GamePage()
    } else if (name === RouteNames.RENDERER) {
      RendererPage()
    } else if (name === RouteNames.MG_OPTIONS) {
      MgOptionsPage()
    }
  }

  // ══════════ 宽屏布局 ══════════
  @Builder
  buildWideLayout() {
    Row() {
      Column() {
        Text('FCL Launcher')
          .fontSize(24).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          .margin({ top: 32, bottom: 32 }).padding({ left: 16 })

        this.buildNavItem('Home', 0)
        this.buildNavItem('Download', 1)
        this.buildNavItem('Manage', 2)
        this.buildNavItem('Servers', 3)
        this.buildNavItem('Account', 4)
        this.buildNavItem('Settings', 5)

        Blank()

        Text(`v${AppVersion.VERSION_NAME}`).fontSize(11).fontColor('#555555').padding(16)
      }
      .width(260).height('100%').backgroundColor('#16213E')

      Column() {
        this.buildPageContent()
      }
      .layoutWeight(1).height('100%')
    }
  }

  // ══════════ 窄屏布局 ══════════
  @Builder
  buildNarrowLayout() {
    Column() {
      Column() {
        this.buildPageContent()
      }
      .layoutWeight(1).width('100%')

      Row() {
        this.buildBottomNav('Home', 0)
        this.buildBottomNav('Down', 1)
        this.buildBottomNav('Manage', 2)
        this.buildBottomNav('Servers', 3)
        this.buildBottomNav('Account', 4)
        this.buildBottomNav('Set', 5)
      }
      .width('100%').height(56).backgroundColor('#16213E')
    }
  }

  @Builder
  buildNavItem(label: string, index: number) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(this.selectedTabIndex === index ? '#E94560' : '#CCCCCC')
        .margin({ left: 12 })
    }
    .width('100%').height(48)
    .onClick(() => this.selectTab(index))
    .backgroundColor(this.selectedTabIndex === index ? 'rgba(233,69,96,0.15)' : 'transparent')
    .borderRadius(8)
    .margin({ left: 8, right: 8, bottom: 4 })
  }

  @Builder
  buildBottomNav(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(this.selectedTabIndex === index ? '#E94560' : '#999999')
    }
    .layoutWeight(1).justifyContent(FlexAlign.Center).height(56)
    .onClick(() => this.selectTab(index))
  }

  @Builder
  buildPageContent() {
    if (this.selectedTabIndex === 0) {
      MainPage()
    } else if (this.selectedTabIndex === 1) {
      DownloadPage()
    } else if (this.selectedTabIndex === 2) {
      ManagePage()
    } else if (this.selectedTabIndex === 3) {
      MultiplayerPage()
    } else if (this.selectedTabIndex === 4) {
      AccountPage()
    } else if (this.selectedTabIndex === 5) {
      SettingsPage()
    }
  }
}
