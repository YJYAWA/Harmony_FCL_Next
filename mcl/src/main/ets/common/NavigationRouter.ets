/**
 * Navigation 路由系统
 * 所有页面路由定义和 Builder 映射
 */
import { GameLogViewer } from '../view/common/GameLogViewer';
import { FileBrowser, FileBrowserConfig } from '../view/common/FileBrowser';
import { CrashReportView } from '../view/common/CrashReporter';
import { VersionDetailPage } from '../view/version/VersionDetailPage';
import { VersionsPage } from '../view/version/VersionsPage';
import { WorldManagePage } from '../view/manage/WorldManagePage';
import { AboutPage } from '../view/setting/AboutPage';
import { JavaManagePage } from '../view/setting/JavaManagePage';
import { ControlEditor } from '../view/control/ControlEditor';

export class RouteNames {
  static readonly MAIN = 'main';
  static readonly SETTINGS = 'settings';
  static readonly ACCOUNT = 'account';
  static readonly DOWNLOAD = 'download';
  static readonly MANAGE = 'manage';
  static readonly MULTIPLAYER = 'multiplayer';
  static readonly GAME_LOG = 'gameLog';
  static readonly FILE_BROWSER = 'fileBrowser';
  static readonly CRASH_REPORT = 'crashReport';
  static readonly VERSION_DETAIL = 'versionDetail';
  static readonly VERSIONS = 'versions';
  static readonly WORLD_MANAGE = 'worldManage';
  static readonly ABOUT = 'about';
  static readonly JAVA_MANAGE = 'javaManage';
  static readonly CONTROL_EDITOR = 'controlEditor';
  static readonly GAME = 'game';
  static readonly RENDERER = 'renderer';
}

@Builder
export function buildRoutePage(name: string, param: ESObject): void {
  if (name === RouteNames.VERSION_DETAIL) {
    VersionDetailPage({ versionId: (param as Record<string, string>)?.['versionId'] ?? '' });
  } else if (name === RouteNames.VERSIONS) {
    VersionsPage();
  } else if (name === RouteNames.WORLD_MANAGE) {
    WorldManagePage();
  } else if (name === RouteNames.ABOUT) {
    AboutPage();
  } else if (name === RouteNames.JAVA_MANAGE) {
    JavaManagePage();
  } else if (name === RouteNames.GAME_LOG) {
    GameLogViewer();
  } else if (name === RouteNames.CRASH_REPORT) {
    CrashReportView();
  } else if (name === RouteNames.FILE_BROWSER) {
    FileBrowser({ config: (param as FileBrowserConfig) ?? defaultFileBrowserConfig });
  } else if (name === RouteNames.CONTROL_EDITOR) {
    ControlEditor();
  }
}

const defaultFileBrowserConfig: FileBrowserConfig = { selectionMode: 'file' };

export class NavigationService {
  private static _stack: NavPathStack | null = null;
  static init(s: NavPathStack): void { NavigationService._stack = s; }
  static get stack(): NavPathStack {
    if (!NavigationService._stack) throw new Error('Nav not initialized');
    return NavigationService._stack;
  }
  static push(name: string, param?: ESObject): void { NavigationService.stack.pushPath({ name, param }); }
  static pop(): void { NavigationService.stack.pop(); }
  static popToRoot(): void { NavigationService.stack.clear(); }
}
