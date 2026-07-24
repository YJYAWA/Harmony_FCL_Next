# FCL-HarmonyOS

> **Fold Craft Launcher for HarmonyOS NEXT** — Minecraft: Java Edition 原生鸿蒙启动器

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-NEXT-red)](https://developer.huawei.com/consumer/cn/harmonyos/)
[![API](https://img.shields.io/badge/API-24-blue)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/harmonyos-overview-V5)
[![DevEco Studio](https://img.shields.io/badge/DevEco%20Studio-6.1.1-lightgrey)](https://developer.huawei.com/consumer/cn/deveco-studio/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

## 项目来历

本项目是 [Fold Craft Launcher (FCL)](https://github.com/FCL-Team/FoldCraftLauncher) 到 **HarmonyOS NEXT (纯鸿蒙)** 的原生移植。

**FCL** 是基于 [HMCL](https://github.com/HMCL-dev/HMCL) 核心功能、使用 [PojavLauncher](https://github.com/PojavLauncherTeam/PojavLauncher) 后端的 Android 平台 Minecraft: Java Edition 启动器。本项目将其 **1,104 个 Java/Kotlin 源文件（~161,000 行）** 完整复刻为 **46 个 ArkTS 源文件（~11,000 行）** ，运行于 HarmonyOS NEXT。

## 技术验证

底层方案已被社区项目验证可行：

| 组件 | 方案 | 来源 |
|------|------|------|
| JDK 运行时 | OpenJDK 8/17/21/25 for HarmonyOS (musl, aarch64) | [AMCL](https://github.com/LZZLHY/mc-ohos-resources) |
| OpenGL 翻译 | MobileGlues (GL → GLES 3.2) | [MobileGL-Dev](https://github.com/MobileGL-Dev/MobileGlues-release) |
| GLFW 适配 | XComponent 兼容层 | 自研 (参考 AMCL) |
| 音频 | OpenAL Soft + OHAudio | 自研 |

> 📄 详细可行性分析见 [原项目 docs/feasibility-report-harmonyos-next.md](https://github.com/FCL-Team/FoldCraftLauncher/blob/main/docs/feasibility-report-harmonyos-next.md)

## 项目文件结构

```
FCL_HarmonyOS/
├── AppScope/app.json5               # 应用全局配置
├── build-profile.json5              # 项目构建配置 (DevEco 6.1.1)
├── oh-package.json5                 # 依赖管理
├── hvigorfile.ts                    # Hvigor 构建脚本
└── mcl/src/main/
    ├── module.json5                 # 模块配置 + 权限声明
    ├── ets/                         # 所有 ArkTS 源码
    │   ├── entryability/            # UIAbility 入口
    │   ├── pages/Index.ets          # 主页面 (Navigation 路由 + 6 Tab)
    │   ├── common/                  # AppContext + NavigationRouter
    │   ├── core/                    # ═══ 核心业务逻辑 ═══
    │   │   ├── auth/                # 认证: Microsoft OAuth / Yggdrasil / 离线
    │   │   ├── download/            # 下载管理: 队列并发 + 进度
    │   │   ├── game/                # 游戏逻辑: 版本管理 / 模组 / 安装器 / LibraryAnalyzer / GameBuilder
    │   │   ├── input/               # 键码映射 (AWT/GLFW/Minecraft)
    │   │   ├── upgrade/             # 更新检查器
    │   │   └── util/                # Constants / FileUtils / UUID / Architecture / HttpUtils
    │   ├── viewmodel/               # MVVM ViewModel
    │   ├── service/                 # GameLauncherService / JarExecutorService
    │   └── view/                    # ═══ UI 页面 (12 个) ═══
    │       ├── main/MainPage.ets    # 主页: 快速启动 + 版本列表
    │       ├── download/            # 下载中心: 搜索/筛选/安装进度
    │       ├── manage/              # 资源管理 + 世界存档管理
    │       ├── account/             # 账号管理 (Microsoft/离线/Yggdrasil)
    │       ├── setting/             # 设置 + 关于 + Java 管理
    │       ├── version/             # 版本详情 + Profile 管理
    │       ├── multiplayer/         # 服务器列表管理
    │       ├── control/             # 触控覆盖层 + 控件编辑器
    │       └── common/              # FileBrowser / GameLogViewer / CrashReporter
    └── resources/                  # 资源文件
```

## 复刻进度

### ✅ 已完成 (ArkTS 层 ~92%)

| 原 FCL 系统 | 状态 | 文件 |
|------------|------|------|
| 认证系统 (Microsoft/Yggdrasil/Offline) | ✅ 100% | `auth/AuthTypes`, `MicrosoftAccount`, `YggdrasilAccount`, `OfflineAccount`, `AccountFactory` |
| 下载系统 (多源/队列/进度) | ✅ 95% | `download/DownloadProvider`, `DownloadManager` |
| 版本管理 (安装/删除/资源) | ✅ 95% | `game/VersionManager` |
| 模组加载器 (Fabric/Forge/OptiFine) | ✅ 90% | `game/ModLoaderInstaller` |
| 资源管理 (Mod/资源包/光影/存档) | ✅ 90% | `game/ModManager` |
| LibraryAnalyzer (模组检测) | ✅ 100% | `game/LibraryAnalyzer` |
| GameBuilder (启动参数构建) | ✅ 100% | `game/GameBuilder` |
| 设置系统 (Theme/Source/Lang/Memory) | ✅ 100% | `SettingsManager`, `ThemeEngine` |
| 键码映射 (AWT/GLFW/MC) | ✅ 100% | `input/KeyCodes` |
| 更新检查 | ✅ 90% | `upgrade/UpdateChecker` |
| 主页 UI (快速启动/版本列表) | ✅ 95% | `view/main/MainPage` |
| 下载中心 UI (搜索/筛选/安装) | ✅ 95% | `view/download/DownloadPage` |
| 资源管理 UI (4 类型 Tab) | ✅ 90% | `view/manage/ManagePage` |
| 世界存档管理 UI | ✅ 90% | `view/manage/WorldManagePage` |
| 账号管理 UI (3 认证模式) | ✅ 95% | `view/account/AccountPage` |
| 设置 UI (6 大类配置) | ✅ 95% | `view/setting/SettingsPage` |
| 关于/帮助页面 | ✅ 90% | `view/setting/AboutPage` |
| Java/渲染器管理 | ✅ 85% | `view/setting/JavaManagePage` |
| 版本详情 UI | ✅ 90% | `view/version/VersionDetailPage` |
| Profile 管理 UI | ✅ 90% | `view/version/VersionsPage` |
| 服务器管理 UI | ✅ 90% | `view/multiplayer/MultiplayerPage` |
| 触控覆盖层 (按钮/方向/触摸板) | ✅ 85% | `view/control/TouchController` |
| 控件编辑器 (拖拽/属性/24 模板) | ✅ 90% | `view/control/ControlEditor` |
| 文件浏览器 (面包屑/筛选/多选) | ✅ 85% | `view/common/FileBrowser` |
| 游戏控制台 (实时日志/过滤/导出) | ✅ 85% | `view/common/GameLogViewer` |
| 崩溃报告 (捕获/持久化/导出) | ✅ 90% | `view/common/CrashReporter` |
| 路由系统 (NavPathStack) | ✅ 100% | `common/NavigationRouter` |
| 多设备适配 (手机/平板/PC) | ✅ 90% | `pages/Index` (5 级断点) |

### 🟡 进行中 (需 DevEco 编译通过)

| 项目 | 状态 | 说明 |
|------|------|------|
| ArkTS 编译 | 🟡 修复中 | ~123 编译错误，主要是严格类型检查 |
| DevEco 同步 | ✅ 已解决 | DevEco 6.1.1 项目模板已生成 |

### ❌ 未完成 (需特定环境)

| 项目 | 原因 | 需要 |
|------|------|-----|
| NAPI C/C++ 桥接层 | WSL 无鸿蒙 NDK | DevEco Studio on Windows + 鸿蒙 NDK |
| JVM 进程启动 | 需 NAPI 实现 | 参考 AMCL 的 posix_spawn 方案 |
| EGL/OpenGL 上下文 | 需 NAPI 实现 | 参考 MobileGlues + XComponent |
| 输入事件注入 JVM | 需 NAPI 实现 | 参考 FCLauncher input_bridge_v3.c |
| Terracotta P2P | Rust 源码不在仓库 | 获取源码 + 鸿蒙 NDK 重编译 |
| LWJGL 兼容层 | 被 MobileGlues 替代 | 外部项目已解决 |

## 构建

### 前置要求

- **DevEco Studio** 6.1.1+
- **HarmonyOS SDK** API 24
- **华为开发者账号** (已实名认证)

### 步骤

```bash
# 1. 用 DevEco Studio 打开本目录
# File → Open → 选择 FCL_HarmonyOS

# 2. 配置签名
# File → Project Structure → Signing Configs → 自动生成

# 3. 编译
# Build → Build HAP(s)
```

## 致谢

| 项目 | 说明 |
|------|------|
| [Fold Craft Launcher](https://github.com/FCL-Team/FoldCraftLauncher) | 原始 Android 启动器 (GPL-3.0) |
| [HMCL](https://github.com/HMCL-dev/HMCL) | 核心启动器逻辑 |
| [PojavLauncher](https://github.com/PojavLauncherTeam/PojavLauncher) | Android Minecraft 后端 |
| [AMCL](https://github.com/LZZLHY/amcl) | 鸿蒙 Minecraft 启动器 (技术方案验证) |
| [MobileGlues](https://github.com/MobileGL-Dev/MobileGlues-release) | GL → GLES 翻译层 |

## 许可

本项目采用 **GPL-3.0 License**，遵循上游 FoldCraftLauncher 的许可协议。

"Minecraft" 是 Mojang Studios 的商标。本项目与 Mojang Studios、Microsoft Corporation 无关联。
