# HarmonyFCL Next

> **HarmonyOS NEXT（纯血鸿蒙）原生 Minecraft: Java Edition 启动器** — 无容器、无 Android 运行时，JVM 进程内嵌入。

本仓库是 [Mr-ETsir/FCL-HarmonyOS](https://github.com/Mr-ETsir/FCL-HarmonyOS) 的原生层补全版：
把 [AMCL](https://github.com/LZZLHY/amcl) 已在真机验证的完整原生栈（JVM 嵌入、GLFW 兼容层、
MobileGlues / MobileGL 渲染器、OpenAL 音频）移植进来，使这个启动器从"ArkTS 界面骨架"
变成**可以真正启动游戏的应用**。

姊妹项目：[HarmonyFCL](https://github.com/YJYAWA/HarmonyFCL)（Android 侧方案——卓易通容器 +
麒麟 SoC 适配）。本项目与其互补：**原生鸿蒙路线，不依赖任何 Android 容器**。

## 它解决什么问题

上游 FCL-HarmonyOS 复刻了 FCL 的 46 个 ArkTS 文件（~11,000 行），但有四个"坎"没过：

1. **NAPI C/C++ 桥接层完全缺失** — `launchJVM` 是注释里的 TODO，`JarExecutorService`
   返回伪造的"安装成功"。本 fork 从 AMCL 移植了整套 JVM 嵌入栈（自研 ELF loader 绕过
   MAP_XPM 签名校验加载 libjvm.so + OHOS sigchain 信号桥 + `JNI_CreateJavaVM` 进程内嵌入）。
2. **图形栈为零** — 没有 XComponent 页面、没有 GL。本 fork 移植 AMCL 的 GLFW 兼容层 +
   MobileGlues（GL→GLES 3.2）+ MobileGL（DirectVulkan）+ OpenAL（OHAudio 后端）。
3. **约 40 处 ArkTS 严格模式编译错误 + 30 处死 import** — 全部修复，51 个编译错误清零，
   `hvigorw assembleHap` 可以一键出包。
4. **安装器 mock** — Forge/Fabric/OptiFine 安装器此前拿到的是伪造成功。现在走
   fork 子进程 + 真实 JVM（从 jar manifest 读取 Main-Class）。

## 本 fork 改了什么

| 改动 | 说明 |
|---|---|
| 原生层全量移植 | AMCL 的 `libentry/libglfw/libamcl_gl_host/libamcl_input_runtime/libamcl_graphics_runtime/libamcl_window_host/libamcl_vulkan_wsi/libamcl_lwjgl_egl/libopenal/libjni_reregister` 全 target |
| JVM 启动路径 | FCL 的 `buildLaunchCommand` argv 模型 → native 侧解析（`-Xmx`/`-cp`/主类/`--gameDir`）→ AMCL `jvmInit` + `jvmCallMain` |
| 安装器子进程 | `fcl_fork_jar.cpp`：纯 C ZIP manifest 解析（不依赖 JVM）+ AMCL fork 保留协议 |
| 关键适配 | 移除 AMCL 的 `-Djava.system.class.loader=AmclClassLoader`（FCL 无 amcl-launcher.jar，注入必炸 `JNI_CreateJavaVM`） |
| 游戏页面 | 全屏 XComponent（`libraryname: 'entry'`，AMCL 同款接法）+ 触控覆盖层 |
| 渲染器管理 | 新增 MobileGlues / **MobileGL**（MC 26.3+ 需要）选项 |
| ArkTS 修复 | 51 个严格模式编译错误清零（Kit 导出名、索引访问类型重设计、`util.TextEncoder` 替换等） |
| 应用身份 | 包名 `com.harmony.fcl`（与 HarmonyFCL 一致）、应用名 HarmonyFCL_Next、HarmonyFCL 图标 |

## 应用身份

| 项 | 值 |
|---|---|
| bundleName | `com.harmony.fcl` |
| 应用名 | HarmonyFCL_Next |
| 版本 | 1.0.0 (1000000) |
| SDK | HarmonyOS 6.1.1（API 24） |
| 架构 | arm64-v8a |
| 关键权限 | `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`（ACL，JIT 必需） |

## 渲染器

`设置 → Java/渲染器管理`：

- **MobileGlues**（默认）— GL→GLES 3.2 翻译，AMCL 实测 1.20.4 全链路通过。需要
  `AppScope/app.json5` 的 `appEnvironments.NEED_OPENGL=1`（已配置，必须在进程首次 EGL
  调用前生效）。
- **MobileGL** — DirectVulkan 渲染器，**MC 26.3+ 版本需要**。`libmobilegl.so` 随 HAP 分发。
- GL4ES / VirGL / Zink — legacy 路径。

## JDK 运行时

| MC 版本 | JDK | mc-ohos-resources 资产 |
|---|---|---|
| 1.7.10–1.12.2 | 8 | `v8u452-ohos-4` |
| 1.13–1.20.x | 17 | `v17.0.13-ohos-5` → `jdk17-ohos-full-v5.zip` |
| 1.20.5+ | 21 | `v21.0.5-ohos-7` |
| 26.1+ | 25 | `v25.0.4-ohos-1` → `jdk25-ohos-full.zip` |

启动器内下载，或手动解压到沙箱 `filesDir/jdk/<版本>/`（布局 `lib/server/libjvm.so`）。

## 构建

前置：DevEco Studio 6.1.1+（自带 SDK 与 hvigor/ohpm/llvm 工具链）。

```bash
# MobileGlues 源码（GL 翻译层即时编译必需；LGPL 合规也要求随源分发，本仓库已 vendored）
# git clone --depth 1 -b amcl/2.0-ohos https://github.com/LZZLHY/MobileGlues.git mcl/prebuilt/mobileglues/mg_src
#   并 checkout 8b69f7fee6c11a46d325731f29ef6b5008da2878 + git submodule update --init --depth 1

ohpm install
hvigorw --mode module -p module=mcl@default -p product=default assembleHap --no-daemon
# 产物: mcl/build/default/outputs/default/mcl-default-unsigned.hap
```

环境变量：`DEVECO_SDK_HOME` 指向 DevEco SDK（如 `E:\DevEcoStudio\sdk`）。
`openal-soft` 已按 AMCL `deps.lock` pin 到 1.24.3 并打好 OHAudio 补丁，无需额外操作。

## 安装（侧载）与 JIT 权限

本项目**未上架应用市场**，与 AMCL 一样走侧载（流程同
[AMCL 官方安装指南](https://amcl.lovedhy.cn/docs/install-hokit)）：

1. 用 [HoKit](https://www.sydxky.cn/hokit.php)（华为账号授权签名 + USB 一键签装）或
   DevEco 对 unsigned HAP 做个人签名后安装。
2. **JIT 权限**（`ALLOW_WRITABLE_CODE_MEMORY`）是受限权限，"时有时无"。启动报
   「JIT 不可用」时按 [AMCL no-jit 指南](https://amcl.lovedhy.cn/docs/no-jit)：
   **清空全部后台（包括微信）→ 单独打开微信 → 再打开启动器**；仍失败重启设备再试。

## HOA 兼容（在 Android 上运行本 HAP）

[HOA](https://github.com/harmony-on-android/HOA) 可让 OpenHarmony HAP 免修改运行在
Android 11+ arm64 设备上。本项目按其兼容边界做了确认：

- ✅ 标准 HAP 结构（modules.abc + resources.index + libs/arm64-v8a），HapInstaller 可直接解析
- ✅ musl ABI bridge（libb.so）拓扑加载依赖链；Android 上 RWX 匿名映射默认可用，
  **JIT 可用性反而优于部分鸿蒙真机**
- ⚠️ HOA 未实现 Bundle Manager / 后台 Service：`KEEP_BACKGROUND_RUNNING` 等权限被忽略（降级不崩溃）
- ⚠️ HOA 目前支持 SDK 5.0/6.0 ABC 格式；本项目 targetSdk 6.1.1(24)，格式兼容以其适配进展为准

## 它不会做什么

- 不内置 JDK/MC 产物（体积与合规原因，运行期按需下载，来源与校验和见 `runtime/` 说明）
- 不绕过任何设备签名/授权机制——ELF loader 只绕过**应用沙箱内**已下载 libjvm.so 的
  MAP_XPM 校验，这需要 ACL 权限本身被授予
- 不做启动环境检测（与 HarmonyFCL 的立场一致：都用实测过，别想当然）

## 许可与致谢

应用本体 **GPL-3.0**（见 [LICENSE](./LICENSE)）；第三方组件许可见
[NOTICE.md](./NOTICE.md)（MobileGlues / MobileGL / OpenAL Soft 的源码均已随仓库 vendored 以满足 LGPL 合规）。

| 项目 | 说明 |
|---|---|
| [Fold Craft Launcher](https://github.com/FCL-Team/FoldCraftLauncher) | 原始 Android 启动器（GPL-3.0） |
| [HarmonyFCL](https://github.com/YJYAWA/HarmonyFCL) | Android 侧姊妹项目（卓易通容器路线），本仓库 README 与合规结构参考它 |
| [AMCL](https://github.com/LZZLHY/amcl) | 鸿蒙原生启动器，本项目原生层的直接来源（GPL-3.0） |
| [MobileGlues](https://github.com/LZZLHY/MobileGlues) | GL→GLES 翻译层（LGPL-2.1） |
| [PojavLauncher](https://github.com/PojavLauncherTeam/PojavLauncher) | Android Minecraft 后端（输入桥设计血统） |
| [mc-ohos-resources](https://github.com/LZZLHY/mc-ohos-resources) | OpenJDK for HarmonyOS 运行时 |

> **非官方修改版**，与 FoldCraftLauncher 官方团队、AMCL 作者、MobileGlues 官方团队、
> Mojang Studios、Microsoft、华为均无关联或背书。"Minecraft" 是 Mojang Studios 的商标。
