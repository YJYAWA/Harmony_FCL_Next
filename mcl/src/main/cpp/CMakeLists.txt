# ============================================================
# CMakeLists.txt — FCL-HarmonyOS Native 构建配置
#
# 由 AMCL (https://github.com/LZZLHY/amcl, GPL-3.0) 的构建配置改编：
#   - 保留 AMCL 全部原生 target：libentry.so（NAPI + JVM 嵌入 + 下载 + 导出）、
#     libglfw.so（GLFW 兼容层）、libamcl_gl_host.so（MobileGlues）、
#     libamcl_input_runtime.so、libamcl_graphics_runtime.so、
#     libamcl_window_host.so、libamcl_vulkan_wsi.so、libamcl_lwjgl_egl.so、
#     libopenal.so（OHAudio 后端）、libjni_reregister.so、jcocoa/objc stubs
#   - 新增 FCL 适配层 libfcl_native.so：FCL ArkTS 的 NAPI 入口，
#     链接 libentry 并把 launchJVM/executeJar 映射到 AMCL 的 JVM 嵌入栈
#   - 路径适配：AMCL_REPO_ROOT 由 4 级上层改为 3 级上层（mcl/）
# ============================================================
cmake_minimum_required(VERSION 3.5.0)
project(fcl_ohos_native)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# 编译选项：是否包含验证测试代码（发布时关闭）
option(MC_OHOS_BUILD_TESTS "Build feasibility test modules (default product only)" OFF)

# 自更新 HDC 需要 Rust 静态库（AMCL 专属分发体系，FCL 暂不启用）
option(AMCL_ENABLE_SIDELOAD_UPDATE "Enable complete HDC for sideload update" OFF)

option(AMCL_INPUT_SHADOW "Enable typed-input shadow ingress by default" ON)
option(AMCL_GLFW_TYPED_PHYSICAL_DEFAULT
    "Select the typed GLFW physical input backend when no startup override is present" OFF)
option(AMCL_GLFW_RAW_RELATIVE_VERIFIED
    "Assert Gate 0 verified normalizable, cursor-decoupled, unaccelerated deltas" OFF)
option(AMCL_GLFW_API26_RAW_MOUSE_MOTION
    "Declare API 26 complete hardware rawDelta for GLFW raw mouse motion" OFF)
option(AMCL_GLFW_NATIVE_ABSOLUTE_VERIFIED
    "Assert verified native surface-local absolute pointer semantics" OFF)
option(AMCL_GLFW_NATIVE_MOUSE_MONOTONIC_NS_VERIFIED
    "Assert XComponent mouse timestamps use CLOCK_MONOTONIC nanoseconds" OFF)
option(AMCL_INPUT_GATE0_TELEMETRY
    "Build non-routing Gate 0 mouse coordinate/raw-delta telemetry" OFF)
option(AMCL_INPUT_COMPILED_FORMAL_DESKTOP
    "Require the runtime input profile to be formal desktop API 26+" OFF)
option(AMCL_STACK_SAMPLER "Build render-thread native stack sampler (diagnostic)" OFF)
option(AMCL_MG_FRAME_STATS "Build MobileGlues present-boundary frame statistics" OFF)
option(AMCL_MG_FRAME_STATS_GL_SCOPES
    "Install per-GL-call timing scopes (self-perturbing; see AMCL docs)" OFF)
option(AMCL_MG_FRAME_STATS_EXHAUSTIVE "Time every wrapped GL call (high-overhead diagnostic)" OFF)
option(AMCL_MG_UPLOAD_PROBE "Count texture upload enum pairs (per-upload diagnostic)" OFF)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ProductDiagnostics.cmake")

if(AMCL_MG_FRAME_STATS_EXHAUSTIVE AND NOT AMCL_MG_FRAME_STATS_GL_SCOPES)
    message(FATAL_ERROR
        "AMCL_MG_FRAME_STATS_EXHAUSTIVE times every wrapped call and requires "
        "AMCL_MG_FRAME_STATS_GL_SCOPES=ON")
endif()

option(AMCL_MG_UPLOAD_SCHEDULER_LAB
    "Build the rejected MG terrain-upload scheduler laboratory path" OFF)
if(AMCL_MG_UPLOAD_SCHEDULER_LAB AND NOT AMCL_DEVELOPER_DIAGNOSTICS)
    message(FATAL_ERROR "AMCL_MG_UPLOAD_SCHEDULER_LAB is default-only")
endif()
set(AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE "-1" CACHE STRING
    "MG upload lab override: -1=config, 0=off, 1=observe, 2=coalesce")
set_property(CACHE AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE PROPERTY STRINGS -1 0 1 2)
if(NOT AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE MATCHES "^-1$|^[012]$")
    message(FATAL_ERROR
        "AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE must be -1, 0, 1 or 2")
endif()
if(NOT AMCL_MG_UPLOAD_SCHEDULER_LAB AND
   NOT AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE STREQUAL "-1")
    message(FATAL_ERROR
        "AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE requires AMCL_MG_UPLOAD_SCHEDULER_LAB=ON")
endif()

# ============================================================
# MobileGlues 源码路径（即时编译，git submodule 风格的独立 clone）
#   FCL 布局: mcl/prebuilt/mobileglues/mg_src/MobileGlues-cpp
#   （AMCL 原布局: MyApplication/prebuilt/mobileglues/mg_src/MobileGlues-cpp）
# ============================================================
# FCL: cpp -> main -> src -> mcl
get_filename_component(AMCL_REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../.. ABSOLUTE)

# Gate 0 证据门禁（默认全 OFF，零成本）
include(${CMAKE_CURRENT_SOURCE_DIR}/input/Gate0Evidence.cmake)

set(AMCL_GRAPHICS_ARTIFACT_SET "complete" CACHE STRING "Explicit packaged graphics artifact policy" FORCE)
set(AMCL_NATIVE_DESKTOP_ONLY OFF CACHE BOOL "Retired product renderer exclusion" FORCE)
find_package(Git REQUIRED)
if(NOT AMCL_NATIVE_DESKTOP_ONLY)
set(MG_SRC_DIR ${AMCL_REPO_ROOT}/prebuilt/mobileglues/mg_src/MobileGlues-cpp)
if(NOT EXISTS ${MG_SRC_DIR}/CMakeLists.txt)
    message(FATAL_ERROR
        "MobileGlues source not found at ${MG_SRC_DIR}.\n"
        "Run: git clone https://github.com/LZZLHY/MobileGlues.git "
        "${AMCL_REPO_ROOT}/prebuilt/mobileglues/mg_src")
endif()

set(MOBILEGLUES_BUILD_STANDALONE OFF)
set(MOBILEGLUES_AUTO_INIT OFF)
set(MOBILEGLUES_ENABLE_PROFILING OFF)
add_subdirectory(${MG_SRC_DIR} ${CMAKE_CURRENT_BINARY_DIR}/mobileglues)

# The upstream plugin benchmark is a developer tool, not a rendering backend.
if(NOT AMCL_DEVELOPER_DIAGNOSTICS)
    get_target_property(AMCL_MG_PRODUCT_SOURCES mobileglues_core SOURCES)
    list(FILTER AMCL_MG_PRODUCT_SOURCES EXCLUDE REGEX "(^|/)bench/multidraw_bench\\.cpp$")
    set_property(TARGET mobileglues_core PROPERTY SOURCES ${AMCL_MG_PRODUCT_SOURCES})
endif()
if(NOT TARGET MobileGlues::Core)
    message(FATAL_ERROR "MobileGlues embedded core target was not created")
endif()
if(AMCL_MG_FRAME_STATS OR AMCL_MG_FRAME_STATS_EXHAUSTIVE)
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_FRAME_STATS=1)
else()
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_FRAME_STATS=0)
endif()
if(AMCL_MG_FRAME_STATS_GL_SCOPES OR AMCL_MG_FRAME_STATS_EXHAUSTIVE)
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_FRAME_STATS_GL_SCOPES=1)
else()
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_FRAME_STATS_GL_SCOPES=0)
endif()
if(AMCL_MG_FRAME_STATS_EXHAUSTIVE)
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_FRAME_STATS_EXHAUSTIVE=1)
endif()
if(AMCL_MG_UPLOAD_PROBE)
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_UPLOAD_PROBE=1)
else()
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_UPLOAD_PROBE=0)
endif()
target_compile_definitions(mobileglues_core PRIVATE
    AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE=${AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE})
if(AMCL_MG_UPLOAD_SCHEDULER_LAB)
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_UPLOAD_SCHEDULER_LAB=1)
else()
    target_compile_definitions(mobileglues_core PRIVATE AMCL_MG_UPLOAD_SCHEDULER_LAB=0)
endif()

# libentry 复用 MG 的 cJSON（隐藏私有副本）
add_library(amcl_mg_config_json OBJECT
    ${MG_SRC_DIR}/config/cJSON.c
)
set_target_properties(amcl_mg_config_json PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden
)
target_include_directories(amcl_mg_config_json PRIVATE
    ${MG_SRC_DIR}/config
)

# MobileGlues 内容寻址身份头（node 脚本，见 mcl/scripts/）
execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse --verify HEAD
    WORKING_DIRECTORY ${MG_SRC_DIR}
    RESULT_VARIABLE AMCL_MG_GIT_RESULT
    OUTPUT_VARIABLE AMCL_MG_SOURCE_COMMIT
    ERROR_VARIABLE AMCL_MG_GIT_ERROR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(LENGTH "${AMCL_MG_SOURCE_COMMIT}" AMCL_MG_SOURCE_COMMIT_LENGTH)
if(NOT AMCL_MG_GIT_RESULT EQUAL 0 OR
   NOT AMCL_MG_SOURCE_COMMIT_LENGTH EQUAL 40 OR
   NOT AMCL_MG_SOURCE_COMMIT MATCHES "^[0-9a-f]+$")
    message(FATAL_ERROR
        "Cannot identify exact MobileGlues source commit: result=${AMCL_MG_GIT_RESULT} "
        "value='${AMCL_MG_SOURCE_COMMIT}' error='${AMCL_MG_GIT_ERROR}'")
endif()
message(STATUS "FCL MobileGlues source commit: ${AMCL_MG_SOURCE_COMMIT}")

set(AMCL_MG_REPO_DIR "${AMCL_REPO_ROOT}/prebuilt/mobileglues/mg_src")
set(AMCL_MG_IDENTITY_SCRIPT "${AMCL_REPO_ROOT}/scripts/compute-mg-source-identity.mjs")
set(AMCL_MG_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(AMCL_MG_IDENTITY_HEADER "${AMCL_MG_GENERATED_DIR}/amcl_mg_source_identity.h")
set(AMCL_MG_EMBED_BUILD_STANDALONE "${MOBILEGLUES_BUILD_STANDALONE}" CACHE INTERNAL
    "MobileGlues standalone mode included in the embedded source identity" FORCE)
set(AMCL_MG_EMBED_AUTO_INIT "${MOBILEGLUES_AUTO_INIT}" CACHE INTERNAL
    "MobileGlues auto-init mode included in the embedded source identity" FORCE)
set(AMCL_MG_EMBED_PROFILING "${MOBILEGLUES_ENABLE_PROFILING}" CACHE INTERNAL
    "MobileGlues profiling mode included in the embedded source identity" FORCE)
find_program(AMCL_NODE_EXECUTABLE NAMES node node.exe)
if(NOT AMCL_NODE_EXECUTABLE)
    message(FATAL_ERROR
        "Node.js is required to generate the MobileGlues source identity header")
endif()
mark_as_advanced(AMCL_NODE_EXECUTABLE)
add_custom_target(amcl_mg_source_identity ALL
    COMMAND "${AMCL_NODE_EXECUTABLE}" "${AMCL_MG_IDENTITY_SCRIPT}"
        --repo "${AMCL_MG_REPO_DIR}"
        --output "${AMCL_MG_IDENTITY_HEADER}"
        --option "AMCL_MG_FRAME_STATS=${AMCL_MG_FRAME_STATS}"
        --option "AMCL_MG_FRAME_STATS_EXHAUSTIVE=${AMCL_MG_FRAME_STATS_EXHAUSTIVE}"
        --option "AMCL_MG_UPLOAD_SCHEDULER_LAB=${AMCL_MG_UPLOAD_SCHEDULER_LAB}"
        --option "AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE=${AMCL_MG_BUFFER_UPLOAD_MODE_OVERRIDE}"
        --option "AMCL_MG_EMBED_BUILD_STANDALONE=${AMCL_MG_EMBED_BUILD_STANDALONE}"
        --option "AMCL_MG_EMBED_AUTO_INIT=${AMCL_MG_EMBED_AUTO_INIT}"
        --option "AMCL_MG_EMBED_PROFILING=${AMCL_MG_EMBED_PROFILING}"
        --option "MOBILEGLUES_LTO_MODE=${MOBILEGLUES_LTO_MODE}"
        --option "CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    BYPRODUCTS "${AMCL_MG_IDENTITY_HEADER}"
    COMMENT "Computing content-addressed MobileGlues source identity"
    VERBATIM
)
set_source_files_properties("${AMCL_MG_IDENTITY_HEADER}" PROPERTIES GENERATED TRUE)
endif() # MobileGlues build/configuration

# 宿主构建身份（FCL 仓库同样用 git 管理）
execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse --verify HEAD
    WORKING_DIRECTORY ${AMCL_REPO_ROOT}
    RESULT_VARIABLE AMCL_HOST_GIT_RESULT
    OUTPUT_VARIABLE AMCL_HOST_SOURCE_COMMIT
    ERROR_VARIABLE AMCL_HOST_GIT_ERROR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT AMCL_HOST_GIT_RESULT EQUAL 0)
    # FCL 仓库未提交时允许 dirty 身份，不 fail（比 AMCL 宽松，方便本地试验）
    set(AMCL_HOST_SOURCE_COMMIT "fcl-local")
    set(AMCL_HOST_SOURCE_STATE "dirty")
else()
    string(LENGTH "${AMCL_HOST_SOURCE_COMMIT}" AMCL_HOST_SOURCE_COMMIT_LENGTH)
    if(NOT AMCL_HOST_SOURCE_COMMIT_LENGTH EQUAL 40 OR
       NOT AMCL_HOST_SOURCE_COMMIT MATCHES "^[0-9a-f]+$")
        set(AMCL_HOST_SOURCE_COMMIT "fcl-local")
    endif()
    execute_process(
        COMMAND ${GIT_EXECUTABLE} status --porcelain=v1 --untracked-files=no
        WORKING_DIRECTORY ${AMCL_REPO_ROOT}
        RESULT_VARIABLE AMCL_HOST_STATUS_RESULT
        OUTPUT_VARIABLE AMCL_HOST_STATUS
        ERROR_VARIABLE AMCL_HOST_STATUS_ERROR
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT AMCL_HOST_STATUS_RESULT EQUAL 0)
        set(AMCL_HOST_STATUS "dirty")
    endif()
    if(AMCL_HOST_STATUS STREQUAL "")
        set(AMCL_HOST_SOURCE_STATE "clean")
    else()
        set(AMCL_HOST_SOURCE_STATE "dirty")
    endif()
endif()
string(CONCAT AMCL_HOST_BUILD_IDENTITY
    "source=" "${AMCL_HOST_SOURCE_COMMIT}"
    ":state=" "${AMCL_HOST_SOURCE_STATE}"
    ":compiler=" "${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}"
    ":system=" "${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}"
    ":mode=" "${CMAKE_BUILD_TYPE}")
message(STATUS "FCL host build identity: ${AMCL_HOST_BUILD_IDENTITY}")

if(NOT AMCL_NATIVE_DESKTOP_ONLY)
set(AMCL_MG_VERSION_HEADER "${MG_SRC_DIR}/version.h")
foreach(AMCL_MG_VERSION_PART IN ITEMS MAJOR MINOR REVISION PATCH)
    file(STRINGS "${AMCL_MG_VERSION_HEADER}" AMCL_MG_VERSION_LINE
         REGEX "^#define ${AMCL_MG_VERSION_PART} [0-9]+$")
    if(NOT AMCL_MG_VERSION_LINE)
        message(FATAL_ERROR
            "Cannot resolve ${AMCL_MG_VERSION_PART} from ${AMCL_MG_VERSION_HEADER}")
    endif()
    string(REGEX REPLACE
        "^#define ${AMCL_MG_VERSION_PART} ([0-9]+)$" "\\1"
        AMCL_MG_VERSION_${AMCL_MG_VERSION_PART} "${AMCL_MG_VERSION_LINE}")
endforeach()
string(CONCAT AMCL_MG_SEMANTIC_VERSION
    "${AMCL_MG_VERSION_MAJOR}.${AMCL_MG_VERSION_MINOR}."
    "${AMCL_MG_VERSION_REVISION}.${AMCL_MG_VERSION_PATCH}")
message(STATUS "AMCL MobileGlues semantic version: ${AMCL_MG_SEMANTIC_VERSION}")
endif()

# ============================================================
# 源文件收集（按模块分组，与 AMCL 保持一致）
# ============================================================
option(AMCL_DESKTOP_NATIVE_GL_VALIDATE "Build a non-publishable desktop native GL validation variant" OFF)

set(NAPI_SOURCES
    napi/napi_entry.cpp
    napi/napi_helpers.cpp
    napi/napi_jvm.cpp
    platform/native_gl.cpp
    platform/desktop_gamepad.cpp
    napi/napi_desktop.cpp
    napi/napi_mc.cpp
    napi/napi_log.cpp
    napi/napi_input.cpp
    napi/napi_forge.cpp
    napi/napi_export.cpp
    napi/napi_sideload_update.cpp
    napi/napi_tests.cpp
)

set(PLATFORM_SOURCES
    platform/xcomponent.cpp
    platform/env_publication.cpp
    platform/cursor_lock.cpp
    platform/window_event_filter.cpp
    platform/input_source.cpp
    platform/input_channel_policy.cpp
    platform/legacy_ring_discontinuity.cpp
    platform/input_invariants.cpp
    platform/joystick_sector.cpp
    platform/ohos_frame_rate_hint.cpp
    platform/ohos_native_window_telemetry.cpp
    platform/touch_input.cpp
    platform/control_schema_contract.cpp
    platform/touch_interaction.cpp
    platform/source_look_processor.cpp
    platform/mapped_look_producer.cpp
    platform/source_look_producer.cpp
    platform/mouse_synth_touch_source.cpp
    platform/native_mouse_route_policy.cpp
    platform/physical_wheel_quantizer.cpp
    platform/product_input_policy.cpp
    platform/render_scale.cpp
    input/platform_input_ingress.cpp
    input/input_trace.cpp
    input/input_shadow_consumer.cpp
    platform/gpu_info.cpp
    platform/vulkan_probe.cpp
    platform/vulkan_requirement_policy.cpp
    platform/mobilegl_capability.cpp
    platform/mobilegl_capability_driver.cpp
    platform/graphics_plan.cpp
)

if(NOT AMCL_NATIVE_DESKTOP_ONLY)
    list(APPEND PLATFORM_SOURCES platform/mg_config.cpp platform/mg_config_migration.cpp)
endif()

option(AMCL_API26_LINK_PROBE "Build a non-distributable API26 strong-link SDK probe" OFF)
if(AMCL_API26_LINK_PROBE)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "OHOS")
        message(FATAL_ERROR
            "AMCL_API26_LINK_PROBE requires the OHOS API26 native toolchain")
    endif()
    list(APPEND PLATFORM_SOURCES platform/api26_input_link_probe.cpp)
endif()

amcl_gate0_normalize_enabled(AMCL_INPUT_GATE0_TELEMETRY
                             AMCL_GATE0_DEF_AMCL_INPUT_GATE0_TELEMETRY)
if(AMCL_GATE0_DEF_AMCL_INPUT_GATE0_TELEMETRY)
    list(APPEND PLATFORM_SOURCES platform/gate0_input_telemetry.cpp)
endif()

# OpenAL Soft（OHAudio 后端；openal-soft 已按 deps.lock pin 克隆并打补丁）
add_subdirectory(openal ${CMAKE_CURRENT_BINARY_DIR}/openal)

# java-objc-bridge 空实现 stubs
add_library(jcocoa SHARED
    stubs/jcocoa_stub.c
)
add_library(objc.A SHARED
    stubs/objc_stub.c
)

# ============================================================
# libamcl_gl_host.so — MobileGlues provider DSO
# ============================================================
if(NOT AMCL_NATIVE_DESKTOP_ONLY)
    target_compile_definitions(mobileglues_core PRIVATE
        glXGetProcAddress=amclMgRawGlXGetProcAddress
        glXGetProcAddressARB=amclMgRawGlXGetProcAddressARB
        eglGetProcAddress=amclMgRawEglGetProcAddress)
    add_library(amcl_gl_host SHARED
        $<TARGET_OBJECTS:mobileglues_core>
        platform/gl_host.cpp)
    add_dependencies(amcl_gl_host amcl_mg_source_identity)
    target_include_directories(amcl_gl_host PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${MG_SRC_DIR}/include
        ${MG_SRC_DIR}
        ${AMCL_MG_GENERATED_DIR}
        ${CMAKE_CURRENT_BINARY_DIR})
    target_compile_options(amcl_gl_host PRIVATE -fvisibility=hidden)
    target_compile_definitions(amcl_gl_host PRIVATE
        AMCL_MG_BENCHMARK_ENABLED=$<BOOL:${AMCL_DEVELOPER_DIAGNOSTICS}>)
    target_link_libraries(amcl_gl_host PRIVATE
        glslang::glslang
        spirv-cross-c
        libhilog_ndk.z.so)
    target_link_options(amcl_gl_host PRIVATE
        -Wl,--no-undefined
        -Wl,-Bsymbolic-functions
        -Wl,--exclude-libs,ALL
        -Wl,--gc-sections)
    set(AMCL_GL_HOST_VERSION_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/platform/gl_host.version")
    if(NOT AMCL_DEVELOPER_DIAGNOSTICS)
        file(READ "${AMCL_GL_HOST_VERSION_SCRIPT}" AMCL_GL_HOST_PRODUCT_EXPORTS)
        string(REGEX REPLACE "[ \t]*mg_multidraw_bench_(progress|run);\r?\n" ""
            AMCL_GL_HOST_PRODUCT_EXPORTS "${AMCL_GL_HOST_PRODUCT_EXPORTS}")
        set(AMCL_GL_HOST_VERSION_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/gl_host_product.version")
        file(WRITE "${AMCL_GL_HOST_VERSION_SCRIPT}" "${AMCL_GL_HOST_PRODUCT_EXPORTS}")
    endif()
    target_link_options(amcl_gl_host PRIVATE
        "-Wl,--version-script=${AMCL_GL_HOST_VERSION_SCRIPT}")
    set_target_properties(amcl_gl_host PROPERTIES
        CXX_STANDARD 20
        CXX_STANDARD_REQUIRED ON
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN"
        INSTALL_RPATH_USE_LINK_PATH FALSE)
endif()

# ============================================================
# libglfw.so — GLFW/window/input facade
# ============================================================
add_library(glfw SHARED
    glfw/glfw_compat.cpp
    platform/native_gl.cpp
    glfw/graphics_runtime_compat.cpp
    platform/desktop_host_client.cpp
    glfw/glfw_callbacks.cpp
    glfw/glfw_vulkan.cpp
    glfw/ohos_render_scheduler.cpp
    input/adapters/glfw_input_adapter.cpp
    input/adapters/glfw_typed_absolute_route.cpp
    input/adapters/glfw_typed_runtime_dispatch.cpp
    input/adapters/glfw_typed_look_route.cpp
    platform/physical_wheel_quantizer.cpp
    input/adapters/glfw_source_plane_aggregate.cpp
    utils/stack_sampler.cpp
)

add_library(amcl_input_runtime SHARED
    input/source/source_control.cpp
    platform/input_ledger.cpp
    platform/external_held_registry.cpp
    platform/external_held_edge_router.cpp
    platform/legacy_output_runtime.cpp
    platform/legacy_physical_edge_router.cpp
    input/delivery/control_delivery.cpp
    input/delivery/look_execution.cpp
    input/input_latency_observation.cpp
    platform/look_delta_math.cpp
    platform/look_pipeline_stats.cpp
    input/input_interaction_order.cpp
    input/input_state_core.cpp
    input/amcl_input_host_descriptor.cpp
    input/adapters/backend_input_bridge.cpp
    input/adapters/backend_keymaps.cpp
    input/adapters/glfw_input_adapter.cpp
    input/adapters/lwjgl2_event_translate.cpp
    platform/physical_wheel_quantizer.cpp
    platform/desktop_host_client.cpp
    glfw/input_bridge_ohos.c)
target_include_directories(amcl_input_runtime PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(amcl_input_runtime PRIVATE cxx_std_17)
target_compile_options(amcl_input_runtime PRIVATE -funwind-tables -fPIC)
target_compile_definitions(amcl_input_runtime PRIVATE AMCL_DESKTOP_EVENT_BRIDGE=1)
target_link_options(amcl_input_runtime PRIVATE
    -Wl,--no-undefined -Wl,-Bsymbolic-functions
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/input/input_runtime.version")
set_property(TARGET amcl_input_runtime APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/input/input_runtime.version)
target_link_libraries(amcl_input_runtime PRIVATE libhilog_ndk.z.so libdeviceinfo_ndk.z.so dl amcl_graphics_runtime)
target_link_libraries(glfw PRIVATE amcl_input_runtime)

# Vulkan WSI / 窗口宿主 / 中立图形运行时 / LWJGL EGL 桥
add_library(amcl_vulkan_wsi SHARED platform/vulkan_wsi.cpp)
add_library(amcl_window_host SHARED platform/window_host.cpp platform/window_host_core.cpp)
target_include_directories(amcl_window_host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(amcl_window_host PRIVATE cxx_std_17)
target_compile_options(amcl_window_host PRIVATE -fvisibility=hidden)
target_link_options(amcl_window_host PRIVATE -Wl,--no-undefined -Wl,-Bsymbolic-functions)
target_link_libraries(amcl_window_host PRIVATE libhilog_ndk.z.so libnative_window.so)
set_target_properties(amcl_window_host PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH "$ORIGIN" INSTALL_RPATH_USE_LINK_PATH FALSE)
target_include_directories(amcl_vulkan_wsi PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(amcl_vulkan_wsi PRIVATE cxx_std_17)
target_compile_options(amcl_vulkan_wsi PRIVATE -fvisibility=hidden)
target_link_options(amcl_vulkan_wsi PRIVATE -Wl,--no-undefined -Wl,-Bsymbolic-functions)
target_link_libraries(amcl_vulkan_wsi PRIVATE libhilog_ndk.z.so)
add_library(amcl_graphics_runtime SHARED
    platform/graphics_runtime_binding.cpp platform/graphics_observation.cpp platform/graphics_backend_session.cpp
    platform/graphics_egl_context.cpp platform/graphics_features.cpp platform/graphics_gl_lookup.cpp)
target_include_directories(amcl_graphics_runtime PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(amcl_graphics_runtime PRIVATE cxx_std_20)
target_compile_options(amcl_graphics_runtime PRIVATE -fvisibility=hidden -funwind-tables)
target_link_options(amcl_graphics_runtime PRIVATE -Wl,--no-undefined -Wl,-Bsymbolic-functions)
target_link_libraries(amcl_graphics_runtime PRIVATE amcl_window_host dl)
add_library(amcl_lwjgl_egl SHARED platform/lwjgl_egl_bridge.cpp)
target_compile_features(amcl_lwjgl_egl PRIVATE cxx_std_17)
target_compile_options(amcl_lwjgl_egl PRIVATE -fvisibility=hidden -funwind-tables)
target_link_options(amcl_lwjgl_egl PRIVATE -Wl,--no-undefined -Wl,-Bsymbolic-functions
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/platform/lwjgl_egl_bridge.version")
set_property(TARGET amcl_lwjgl_egl APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/platform/lwjgl_egl_bridge.version)
target_link_libraries(amcl_lwjgl_egl PRIVATE dl)
target_link_libraries(glfw PRIVATE amcl_vulkan_wsi amcl_window_host amcl_graphics_runtime)
add_custom_target(amcl_graphics_boundary_compile_gate DEPENDS glfw amcl_vulkan_wsi amcl_window_host amcl_graphics_runtime amcl_lwjgl_egl)
if(TARGET amcl_gl_host)
    add_dependencies(amcl_graphics_boundary_compile_gate amcl_gl_host)
    add_dependencies(glfw amcl_gl_host)
endif()

if(AMCL_NATIVE_DESKTOP_ONLY)
    target_sources(glfw PRIVATE glfw/desktop_egl.cpp)
else()
    target_sources(glfw PRIVATE glfw/glfw_egl.cpp glfw/mg_benchmark_cache.cpp)
endif()
set_target_properties(glfw PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
)

target_include_directories(glfw BEFORE PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
if(NOT AMCL_NATIVE_DESKTOP_ONLY)
    target_include_directories(glfw BEFORE PRIVATE ${MG_SRC_DIR}/include/MG ${MG_SRC_DIR}/config)
endif()

target_compile_options(glfw PRIVATE
    -funwind-tables -fPIC
    $<$<COMPILE_LANGUAGE:CXX>:-D_THREAD_SAFE>
    $<$<COMPILE_LANGUAGE:C>:-std=gnu99>
)

set(AMCL_GLFW_VERSION_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/glfw/glfw_mg.version")
if(AMCL_NATIVE_DESKTOP_ONLY)
    set(AMCL_GLFW_VERSION_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/glfw/glfw_native.version")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${AMCL_GLFW_VERSION_SCRIPT}")
if(NOT AMCL_DEVELOPER_DIAGNOSTICS)
    file(READ "${AMCL_GLFW_VERSION_SCRIPT}" AMCL_GLFW_PRODUCT_EXPORTS)
    string(REGEX REPLACE "[ \t]*mg_multidraw_bench_(progress|run);\r?\n" ""
        AMCL_GLFW_PRODUCT_EXPORTS "${AMCL_GLFW_PRODUCT_EXPORTS}")
    set(AMCL_GLFW_VERSION_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/glfw_mg_product.version")
    file(WRITE "${AMCL_GLFW_VERSION_SCRIPT}" "${AMCL_GLFW_PRODUCT_EXPORTS}")
endif()
target_link_options(glfw PRIVATE
    "-Wl,--version-script=${AMCL_GLFW_VERSION_SCRIPT}"
    "-Wl,-Bsymbolic-functions"
    "-Wl,--gc-sections"
)
set_property(TARGET glfw APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/glfw/glfw_mg.version ${AMCL_GLFW_VERSION_SCRIPT})

if(AMCL_STACK_SAMPLER)
    target_compile_definitions(glfw PRIVATE AMCL_STACK_SAMPLER)
endif()

if(NOT AMCL_NATIVE_DESKTOP_ONLY)
    add_dependencies(glfw amcl_mg_source_identity)
    target_sources(glfw PRIVATE $<TARGET_OBJECTS:amcl_mg_config_json>)
endif()
target_include_directories(glfw PRIVATE "${AMCL_MG_GENERATED_DIR}")
target_compile_definitions(glfw PRIVATE
    AMCL_DESKTOP_EVENT_BRIDGE=1
    AMCL_MG_SEMANTIC_VERSION="${AMCL_MG_SEMANTIC_VERSION}"
    AMCL_HOST_BUILD_IDENTITY="${AMCL_HOST_BUILD_IDENTITY}"
    AMCL_GLFW_TYPED_PHYSICAL_DEFAULT=$<BOOL:${AMCL_GLFW_TYPED_PHYSICAL_DEFAULT}>
    AMCL_GLFW_RAW_RELATIVE_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_RAW_RELATIVE_VERIFIED}
    AMCL_GLFW_API26_RAW_MOUSE_MOTION=$<BOOL:${AMCL_GLFW_API26_RAW_MOUSE_MOTION}>
    AMCL_GLFW_NATIVE_ABSOLUTE_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_NATIVE_ABSOLUTE_VERIFIED}
    AMCL_GLFW_NATIVE_MOUSE_MONOTONIC_NS_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_NATIVE_MOUSE_MONOTONIC_NS_VERIFIED}
    AMCL_GATE0_EVIDENCE_IDS="${AMCL_GATE0_EVIDENCE_IDS_STRING}"
)
target_compile_definitions(amcl_input_runtime PRIVATE
    AMCL_DESKTOP_EVENT_BRIDGE=1
    AMCL_MG_SEMANTIC_VERSION="${AMCL_MG_SEMANTIC_VERSION}"
    AMCL_HOST_BUILD_IDENTITY="${AMCL_HOST_BUILD_IDENTITY}"
    AMCL_GLFW_TYPED_PHYSICAL_DEFAULT=$<BOOL:${AMCL_GLFW_TYPED_PHYSICAL_DEFAULT}>
    AMCL_GLFW_RAW_RELATIVE_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_RAW_RELATIVE_VERIFIED}
    AMCL_GLFW_API26_RAW_MOUSE_MOTION=$<BOOL:${AMCL_GLFW_API26_RAW_MOUSE_MOTION}>
    AMCL_GLFW_NATIVE_ABSOLUTE_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_NATIVE_ABSOLUTE_VERIFIED}
    AMCL_GLFW_NATIVE_MOUSE_MONOTONIC_NS_VERIFIED=${AMCL_GATE0_DEF_AMCL_GLFW_NATIVE_MOUSE_MONOTONIC_NS_VERIFIED}
    AMCL_GATE0_EVIDENCE_IDS="${AMCL_GATE0_EVIDENCE_IDS_STRING}"
)

target_link_libraries(glfw PRIVATE libdeviceinfo_ndk.z.so)
target_link_libraries(glfw PUBLIC
    libhilog_ndk.z.so
    libnative_window.so)
if(AMCL_NATIVE_DESKTOP_ONLY)
    target_link_libraries(glfw PUBLIC libEGL.so)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    target_link_libraries(glfw PRIVATE libqos.so)
endif()

# JVM 嵌入模块 + MC 启动器（AMCL 全栈）
set(JVM_SOURCES
    jvm/jna_runtime_contract.cpp
    jvm/jvm_launcher.cpp
    jvm/game_gui_bridge.cpp
    jvm/game_gui_observation.cpp
    jvm/game_process_exit.cpp
    jvm/mc_launcher.cpp
    jvm/jni_registry.cpp
    jvm/elf_loader.cpp
    jvm/fork_run_java.cpp
    jvm/jvm_common_args.cpp
    jvm/if_inet6_shim.cpp
    utils/amcl_log.cpp
)

# 下载引擎（libcurl 预编译 so）
set(DOWNLOAD_SOURCES
    download/probe.cpp
    download/net_state.cpp
    download/exception.cpp
    download/net_source.cpp
    download/sha1.cpp
    download/hmac_sha256.cpp
    download/relay.cpp
    download/file_checker.cpp
    download/download_meta.cpp
    download/net_thread.cpp
    download/net_file.cpp
    download/loader_download.cpp
    download/engine.cpp
    download/multi_downloader.cpp
    download/config.cpp
    download/napi_bridge.cpp
    download/download_napi.cpp
)

if(CMAKE_SYSTEM_NAME STREQUAL "OHOS" AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set_property(SOURCE
        download/sha1.cpp
        download/hmac_sha256.cpp
        APPEND PROPERTY COMPILE_OPTIONS "$<$<CONFIG:Debug>:-O2>")
endif()

set(EXPORT_SOURCES
    export/export_pipeline.cpp
    export/export_trusted_io.cpp
    export/export_zip_writer.cpp
    export/export_zip_verifier.cpp
)

add_library(curl_imported SHARED IMPORTED)
set_target_properties(curl_imported PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libcurl.so
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include
)

set(TEST_SOURCES "")
if(MC_OHOS_BUILD_TESTS)
    set(TEST_SOURCES
        tests/jit_test.cpp
        tests/jvm_test.cpp
        tests/glfw_test.cpp
        tests/gl4_test.cpp
        tests/mg_test.cpp
        tests/graphics_depth_range_test.cpp
        ../../../../tests/graphics-semantics/depth_range_scene.cpp
        tests/mg_context_identity_test.cpp
        tests/mobilegl_program_test.cpp
        ../../../../tests/graphics-semantics/mg_context_identity_scene.cpp
        ../../../../tests/graphics-semantics/mobilegl_program_scene.cpp
        tests/lwjgl_test.cpp
        tests/amcl_log_concurrent_test.cpp
        tests/sdl3_c2_test.cpp
        tests/sdl3_window_test.cpp
        tests/mobilegl_probe_test.cpp
        tests/ipv6_probe_test.cpp
        tests/ipv6_java_probe_test.cpp
        download/tests/sha1_incremental_test.cpp
        download/tests/text_fetch_test.cpp
        download/tests/source_scoring_test.cpp
        download/tests/error_and_source_lifecycle_test.cpp
    )
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/platform)
endif()

# ============================================================
# libentry.so — 主模块（NAPI + JVM + 下载 + 导出）
# ============================================================
add_library(entry SHARED
    ${NAPI_SOURCES}
    ${PLATFORM_SOURCES}
    ${JVM_SOURCES}
    ${DOWNLOAD_SOURCES}
    ${EXPORT_SOURCES}
    ${TEST_SOURCES}
)
set_target_properties(entry glfw amcl_input_runtime amcl_vulkan_wsi amcl_window_host amcl_graphics_runtime PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN"
    INSTALL_RPATH_USE_LINK_PATH FALSE)
if(NOT AMCL_NATIVE_DESKTOP_ONLY)
    target_sources(entry PRIVATE $<TARGET_OBJECTS:amcl_mg_config_json>)
    target_include_directories(entry PRIVATE ${MG_SRC_DIR}/config)
endif()

set_target_properties(entry PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

target_include_directories(entry PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

if(AMCL_INPUT_SHADOW)
    target_compile_definitions(entry PRIVATE AMCL_INPUT_SHADOW=1)
else()
    target_compile_definitions(entry PRIVATE AMCL_INPUT_SHADOW=0)
endif()

target_compile_definitions(entry PRIVATE
    AMCL_INPUT_GATE0_TELEMETRY=${AMCL_GATE0_DEF_AMCL_INPUT_GATE0_TELEMETRY}
    AMCL_INPUT_COMPILED_FORMAL_DESKTOP=$<BOOL:${AMCL_INPUT_COMPILED_FORMAL_DESKTOP}>
)
target_compile_definitions(entry PRIVATE
    AMCL_GLFW_API26_RAW_MOUSE_MOTION=$<BOOL:${AMCL_GLFW_API26_RAW_MOUSE_MOTION}>)
if(AMCL_API26_LINK_PROBE)
    target_link_libraries(entry PRIVATE libohgame_controller.z.so)
endif()

if(MC_OHOS_BUILD_TESTS)
    target_compile_definitions(entry PRIVATE MC_OHOS_BUILD_TESTS)
endif()

if(AMCL_STACK_SAMPLER)
    target_compile_definitions(entry PRIVATE AMCL_STACK_SAMPLER)
endif()

target_compile_definitions(entry PRIVATE AMCL_NATIVE_DESKTOP_ONLY=$<BOOL:${AMCL_NATIVE_DESKTOP_ONLY}> AMCL_DESKTOP_NATIVE_GL_VALIDATE=$<BOOL:${AMCL_DESKTOP_NATIVE_GL_VALIDATE}>)
target_compile_definitions(glfw PRIVATE AMCL_NATIVE_DESKTOP_ONLY=$<BOOL:${AMCL_NATIVE_DESKTOP_ONLY}> AMCL_DESKTOP_NATIVE_GL_VALIDATE=$<BOOL:${AMCL_DESKTOP_NATIVE_GL_VALIDATE}>)
target_link_libraries(entry PRIVATE amcl_input_runtime libpasteboard.so libudmf.so libdeviceinfo_ndk.z.so amcl_vulkan_wsi amcl_window_host amcl_graphics_runtime)
target_link_libraries(entry PRIVATE libz.so)
target_sources(entry PRIVATE platform/runtime_slot_store.cpp)

if(AMCL_ENABLE_SIDELOAD_UPDATE)
    if(DEFINED ENV{AMCL_HDC_CORE_ARCHIVE})
        set(AMCL_HDC_CORE_ARCHIVE "$ENV{AMCL_HDC_CORE_ARCHIVE}")
    endif()
    if(NOT EXISTS "${AMCL_HDC_CORE_ARCHIVE}")
        message(FATAL_ERROR "Complete HDC archive missing; use build-hdc-core.mjs")
    endif()
    add_library(amcl_hdc_core STATIC IMPORTED)
    set_target_properties(amcl_hdc_core PROPERTIES IMPORTED_LOCATION "${AMCL_HDC_CORE_ARCHIVE}")
    target_link_libraries(entry PRIVATE amcl_hdc_core)
    target_compile_definitions(entry PRIVATE AMCL_ENABLE_SIDELOAD_UPDATE=1)
else()
    target_compile_definitions(entry PRIVATE AMCL_ENABLE_SIDELOAD_UPDATE=0)
endif()

target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libace_ndk.z.so
    libnative_window.so
    libohhidebug.so
    glfw
    curl_imported
)
if(AMCL_NATIVE_DESKTOP_ONLY)
    target_link_libraries(entry PUBLIC libEGL.so)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    target_link_libraries(entry PRIVATE libnative_display_manager.so)
endif()

# ============================================================
# libfcl_native.so — FCL ArkTS 适配层
# 把 FCL 的 launchJVM/executeJar/输入接口映射到 AMCL 的 JVM 嵌入栈。
# 链接 entry（DT_NEEDED）：加载 fcl_native 时自动装载 libentry，
# AMCL 的 Init()（prepareMobileGluesRuntime / XComponent 注册等）随之执行。
# ============================================================
add_library(fcl_native SHARED
    napi/fcl_napi.cpp
    napi/fcl_fork_jar.cpp
)
target_include_directories(fcl_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
set_target_properties(fcl_native PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN"
    INSTALL_RPATH_USE_LINK_PATH FALSE)
target_link_libraries(fcl_native PRIVATE
    libace_napi.z.so
    libhilog_ndk.z.so
    libz.so
    entry
)

# ============================================================
# libjni_reregister.so — Fabric/Forge ClassLoader JNI 重绑
# ============================================================
add_library(jni_reregister SHARED
    glfw/jni_reregister.c
)
target_include_directories(jni_reregister PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(jni_reregister PUBLIC
    dl
    libhilog_ndk.z.so
)

amcl_apply_diagnostic_policy(entry)
amcl_apply_diagnostic_policy(glfw)
amcl_apply_diagnostic_policy(amcl_input_runtime)
if(TARGET amcl_gl_host)
    amcl_apply_diagnostic_policy(amcl_gl_host)
endif()
amcl_apply_diagnostic_policy(amcl_vulkan_wsi)
amcl_apply_diagnostic_policy(amcl_graphics_runtime)
target_link_options(glfw PRIVATE "-Wl,--undefined=amclDiagnosticBuildIdentity")
if(NOT AMCL_NATIVE_DESKTOP_ONLY)
target_include_directories(mobileglues_core PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${MG_SRC_DIR}")
target_compile_options(mobileglues_core PRIVATE
    "-include" "${CMAKE_CURRENT_SOURCE_DIR}/utils/product_mg_logging.h")
endif() # MobileGlues product logging
