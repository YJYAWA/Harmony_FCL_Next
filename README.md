# HarmonyFCL Next

**把 [Fold Craft Launcher (FCL)](https://github.com/FCL-Team/FoldCraftLauncher) 移植到 HarmonyOS NEXT（纯血鸿蒙）的 Minecraft: Java Edition 启动器。原生路线：无容器、无 Android 运行时，JVM 进程内嵌入。**

本仓库 fork 自 [Mr-ETsir/FCL-HarmonyOS](https://github.com/Mr-ETsir/FCL-HarmonyOS)。上游完成了 FCL 的 ArkTS 界面层移植（46 个文件，约 11,000 行），但 NAPI 原生桥是空的——**不能启动游戏**。本 fork 把全部缺失的原生层移植进来，让它成为一台真正能玩的启动器。基线为 FCL 1.3.1.9（移植快照 2026-07-24），现已同步至上游 **FCL 1.3.4.3**（2026-10-30）。

## 本 fork 移植了什么

| 改动 | 说明 |
|---|---|
| JVM 嵌入 | 移植 [AMCL](https://github.com/LZZLHY/amcl) 原生栈：自研 ELF loader 绕过 MAP_XPM 签名校验加载 `libjvm.so`、OHOS sigchain 信号桥、进程内 `JNI_CreateJavaVM`，JDK 8/17/21/25 双布局 |
| 启动链路 | FCL 的 `buildLaunchCommand` argv 模型 → native 解析（`-Xmx`/`-cp`/主类/`--gameDir`）→ `jvmInit` + `jvmCallMain`，游戏 `main()` 返回后回传退出码 |
| 图形栈 | AMCL GLFW 兼容层 + 输入运行时 + 图形运行时 + Vulkan WSI + MobileGlues（GL→GLES 3.2，源码 vendored 即时编译）+ **MobileGL DirectVulkan 渲染器**（MC 26.3+） |
| 音频 | OpenAL Soft 1.24.3 + OHAudio 后端（按 deps.lock pin + 补丁） |
| 渲染器选择 | FCL/HarmonyFCL 同款渲染器管理页（MobileGlues / MobileGL / GL4ES …），选择经 AMCL GraphicsPlan wire 协议激活进启动链路 |
| 游戏页面 | 全屏 XComponent（`libraryname: 'entry'`）+ 触控覆盖层 |
| 安装器子进程 | fork + 真实 JVM（纯 C 解析 jar manifest 取 Main-Class），替换上游的伪造成功 |
| ArkTS 修复 | 上游 51 个严格模式编译错误清零，`hvigorw assembleHap` 一键出包 |
| 上游同步 | 跟进 FCL 1.3.4.0–1.3.4.3：FML `earlyWindowControl` 版本分流修复、MobileGlues 运行时选项齿轮配置、OSMesa/VirGL 内置渲染器剥离（对应条目移除） |
| 无更新提示 | 彻底移除应用内更新检查与更新提示（`core/upgrade/UpdateChecker` 已删除），启动器不再联网查询上游 Release |
| 关键适配 | 移除 AMCL 的 `-Djava.system.class.loader=AmclClassLoader`（FCL 无 amcl-launcher.jar，注入必炸 `JNI_CreateJavaVM`） |
| 应用身份 | 包名 `com.harmony.fcl`、应用名 HarmonyFCL_Next、版本 `1.3.4.3-next.1` |

## 应用身份

| 项 | 值 |
|---|---|
| bundleName | `com.harmony.fcl` |
| 应用名 | HarmonyFCL_Next |
| 版本 | 1.3.4.3-next.1 (1030403)，对应 FCL 上游 1.3.4.3 |
| SDK | HarmonyOS 6.1.1（API 24） |
| 架构 | arm64-v8a |
| 关键权限 | `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`（ACL，JIT 必需） |

## 渲染器

`Java/渲染器管理` 页（对齐 FCL/HarmonyFCL 的选择体验）：

- **MobileGlues**（默认，推荐）— GL→GLES 3.2 翻译，AMCL 真机全链路验证（1.20.4）。需 `AppScope/app.json5` 的 `appEnvironments.NEED_OPENGL=1`（已配置）。
- **MobileGL** — DirectVulkan 渲染器，**MC 26.3+ 必选**。`libmobilegl.so` 随 HAP 分发。
- **GL4ES** — legacy（LWJGL2 时代版本）。
- Auto-detect — 自动匹配基线。
- ⚙ 齿轮入口（MobileGlues 行尾）— 对齐上游 FCL 1.3.4.3「内置渲染器行尾齿轮配置」，可调 MobileGlues 全量运行时选项（ANGLE、无错误模式、自定义 GL 版本、GLSL 缓存、FSR1 超分、深度清理修复模式等），仅显式配置过的键会合并写入 `files/MG/config.json`。

选择持久化于 `SettingsManager.renderer`，启动时经 `launchJVM` 第 4 参进 native，按 AMCL
`GraphicsBackendPlan.serializeGraphicsPlan` 的 wire 协议构造 GraphicsPlan 并
`ActivateGraphicsPlan` 激活（MobileGL = `minecraft-vulkan/SDL3/26.3 保守基线`），
`jvmInit` 注入 `-Damcl.graphics.profile`。计划被拒不阻断启动，回退默认并留日志。

## JDK 运行时

来源 [mc-ohos-resources](https://github.com/LZZLHY/mc-ohos-resources)（OpenJDK for HarmonyOS, musl/aarch64）：

| MC 版本 | JDK | 资产 |
|---|---|---|
| 1.7.10–1.12.2 | 8 | `v8u452-ohos-4` |
| 1.13–1.20.x | 17 | `v17.0.13-ohos-5` |
| 1.20.5+ | 21 | `v21.0.5-ohos-7` |
| 26.1+ | 25 | `v25.0.4-ohos-1` |

启动器内下载，或手动解压到沙箱 `filesDir/jdk/<版本>/`（布局 `lib/server/libjvm.so`）。

## 构建

前置：DevEco Studio 6.1.1+（自带 SDK 与 hvigor/ohpm 工具链）。

```bash
# MobileGlues 源码（GL 翻译层即时编译必需；本仓库已 vendored，clone 后跳过此步）
# git clone --depth 1 -b amcl/2.0-ohos https://github.com/LZZLHY/MobileGlues.git mcl/prebuilt/mobileglues/mg_src
#   并 checkout 8b69f7fee6c11a46d325731f29ef6b5008da2878 + git submodule update --init --depth 1

ohpm install
hvigorw --mode module -p module=mcl@default -p product=default assembleHap --no-daemon
# 产物: mcl/build/default/outputs/default/mcl-default-unsigned.hap
```

环境变量 `DEVECO_SDK_HOME` 指向 DevEco SDK。`openal-soft` 已 pin 到 1.24.3 并打好
OHAudio 补丁，无需额外操作。

## 安装（侧载）与 JIT

本项目**未上架应用市场**，走侧载（同 [AMCL 官方指南](https://amcl.lovedhy.cn/docs/install-hokit)）：

1. [HoKit](https://www.sydxky.cn/hokit.php)（华为账号授权签名 + USB 一键签装）或 DevEco 对 unsigned HAP 个人签名后安装。
2. JIT 权限"时有时无"时按 [AMCL no-jit 指南](https://amcl.lovedhy.cn/docs/no-jit)：**清空全部后台（包括微信）→ 单独打开微信 → 再打开启动器**；仍失败重启设备。

## HOA（在 Android 上运行本 HAP）

[HOA](https://github.com/harmony-on-android/HOA) 可让 OpenHarmony HAP 免修改运行在 Android 11+ arm64 上：

- ✅ 标准 HAP 结构，HapInstaller 可解析；musl bridge 拓扑加载依赖链
- ✅ Android 上 RWX 匿名映射默认可用，**JIT 可用性反而优于部分鸿蒙真机**
- ⚠️ Bundle Manager / 后台 Service 未实现（权限被忽略，降级不崩溃）；SDK 6.1.1 ABC 格式支持以其适配进展为准

## 致谢

| 项目 | 说明 |
|---|---|
| [Fold Craft Launcher](https://github.com/FCL-Team/FoldCraftLauncher) | 原始 Android 启动器（GPL-3.0），本项目移植的对象 |
| [FCL-HarmonyOS](https://github.com/Mr-ETsir/FCL-HarmonyOS) | fork 来源：FCL 的 ArkTS 界面层移植 |
| [HarmonyFCL](https://github.com/YJYAWA/HarmonyFCL) | Android 侧姊妹项目（卓易通容器路线），本仓库结构与 FCL 上游同步参考 |
| [AMCL](https://github.com/LZZLHY/amcl) | 鸿蒙原生启动器，本项目原生层（JVM 嵌入/GLFW/输入/下载引擎）的直接来源（GPL-3.0） |
| [MobileGlues](https://github.com/LZZLHY/MobileGlues) | GL→GLES 3.2 翻译层，amcl/2.0-ohos 分支 vendored（上游 [MobileGL-Dev](https://github.com/MobileGL-Dev/MobileGlues-release)） |
| [MobileGL](https://github.com/LZZLHY/MobileGL) | DirectVulkan 渲染器（MC 26.3+） |
| [OpenAL Soft](https://github.com/kcat/openal-soft) | 3D 音频库 + AMCL OHAudio 后端补丁 |
| [LWJGL](https://github.com/LWJGL/lwjgl3) | Minecraft 的 Java 游戏库绑定（native 库随 HAP 分发） |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | EGL/GLES 用户态驱动 |
| [curl](https://github.com/curl/curl) | 下载引擎的 HTTP 层 |
| [glslang](https://github.com/KhronosGroup/glslang) / [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) | Vulkan 着色器工具链（MobileGlues 依赖） |
| [PojavLauncher](https://github.com/PojavLauncherTeam/PojavLauncher) | Android Minecraft 后端（输入桥 input_bridge_v3 设计血统） |
| [HMCL](https://github.com/HMCL-dev/HMCL) | FCL 的核心启动器逻辑来源 |
| [mc-ohos-resources](https://github.com/LZZLHY/mc-ohos-resources) | OpenJDK for HarmonyOS 运行时 |
| [HOA](https://github.com/harmony-on-android/HOA) | 在 Android 上运行 OpenHarmony HAP |

## 许可

应用本体 **GPL-3.0**（见 [LICENSE](./LICENSE)）；第三方组件许可见 [NOTICE.md](./NOTICE.md)
（MobileGlues / OpenAL Soft 源码已随仓库 vendored 以满足 LGPL 合规）。

> **非官方修改版**，与 FoldCraftLauncher 官方团队、AMCL 作者、MobileGlues 官方团队、
> Mojang Studios、Microsoft、华为均无关联或背书。"Minecraft" 是 Mojang Studios 的商标。
