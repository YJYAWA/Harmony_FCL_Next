# NOTICE — 第三方组件与许可声明

HarmonyFCL Next 的应用本体采用 **GPL-3.0-only**（见 [LICENSE](./LICENSE)）。本项目是
[FoldCraftLauncher](https://github.com/FCL-Team/FoldCraftLauncher) 及其鸿蒙移植
[Mr-ETsir/FCL-HarmonyOS](https://github.com/Mr-ETsir/FCL-HarmonyOS) 的 GPL-3.0 衍生作品。

原生层核心来自 [AMCL](https://github.com/LZZLHY/amcl)（GPL-3.0），按其仓库内文件逐份保留原始版权与说明注释。

| 组件 | 许可 | 来源 | 引入方式 |
|---|---|---|---|
| AMCL 原生栈（elf_loader / jvm_launcher / mc_launcher / glfw 兼容层 / 输入桥 / 下载引擎 / XComponent 适配） | GPL-3.0 | github.com/LZZLHY/amcl | 源码 vendored（`mcl/src/main/cpp/`），保留原文件头声明 |
| MobileGlues（GL→GLES 翻译层） | LGPL-2.1-only | github.com/LZZLHY/MobileGlues（amcl/2.0-ohos 分支 @8b69f7fe） | 源码 vendored（`mcl/prebuilt/mobileglues/mg_src/`），提供完整对应源码以满足 LGPL |
| MobileGL（DirectVulkan 渲染器，MC 26.3+） | LGPL-3.0 | github.com/LZZLHY/MobileGL（经 AMCL 预编译分发） | 预编译 `libs/arm64-v8a/libmobilegl.so` |
| OpenAL Soft + OHAudio 后端 | LGPL-2.1（库）/ 补丁随 AMCL | github.com/kcat/openal-soft @1.24.3（mirror pin dc7d705） | 源码 vendored（`mcl/src/main/cpp/openal/openal-soft/`）+ AMCL OHAudio 补丁 |
| LWJGL 生态 native 库 | BSD-3-Clause | lwjgl.org | 预编译 `libs/arm64-v8a/liblwjgl*.so` |
| Mesa (EGL/gallium/glapi) | MIT | mesa.freedesktop.org | 预编译 `libs/arm64-v8a/lib*_mesa*.so` |
| libcurl | MIT (curl) | curl.se | 预编译 `libs/arm64-v8a/libcurl.so` |
| glslang | Apache-2.0（含 Khronos 特例） | github.com/KhronosGroup/glslang | MobileGlues 3rdparty vendored |
| SPIRV-Cross | Apache-2.0 | github.com/KhronosGroup/SPIRV-Cross | MobileGlues 3rdparty vendored |
| glm / xxhash / FastSTL / ska | 各自上游许可 | 见各源码树 LICENSE | MobileGlues 3rdparty vendored |
| OpenJDK for HarmonyOS | GPL-2.0 with Classpath Exception | github.com/LZZLHY/mc-ohos-resources | 运行期下载，不随 HAP 分发 |
| PojavLauncher（input_bridge_v3 设计血统） | GPL-3.0 | github.com/PojavLauncherTeam/PojavLauncher | 设计参考（经 AMCL 适配层） |

**免责声明**：本项目与 FoldCraftLauncher 官方团队、AMCL 作者、MobileGlues 官方团队、
Mojang Studios、Microsoft Corporation、华为均无关联或背脚。"Minecraft" 是 Mojang Studios 的商标。
