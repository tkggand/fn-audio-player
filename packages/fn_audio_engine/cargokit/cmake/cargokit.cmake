SET(cargokit_cmake_root "${CMAKE_CURRENT_LIST_DIR}/..")

# Workaround for https://github.com/dart-lang/pub/issues/4010
get_filename_component(cargokit_cmake_root "${cargokit_cmake_root}" REALPATH)

if(WIN32)
    # REALPATH does not properly resolve symlinks on windows :-/
    execute_process(COMMAND powershell -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_LIST_DIR}/resolve_symlinks.ps1" "${cargokit_cmake_root}" OUTPUT_VARIABLE cargokit_cmake_root OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

# Arguments
# - target: CMAKE target to which rust library is linked
# - manifest_dir: relative path from current folder to directory containing cargo manifest
# - lib_name: cargo package name
# - any_symbol_name: name of any exported symbol from the library.
#                    used on windows to force linking with library.
function(apply_cargokit target manifest_dir lib_name any_symbol_name)

    set(CARGOKIT_LIB_NAME "${lib_name}")
    set(CARGOKIT_LIB_FULL_NAME "${CMAKE_SHARED_MODULE_PREFIX}${CARGOKIT_LIB_NAME}${CMAKE_SHARED_MODULE_SUFFIX}")
    if (CMAKE_CONFIGURATION_TYPES)
        set(CARGOKIT_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>")
        set(OUTPUT_LIB "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/${CARGOKIT_LIB_FULL_NAME}")
    else()
        set(CARGOKIT_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}")
        set(OUTPUT_LIB "${CMAKE_CURRENT_BINARY_DIR}/${CARGOKIT_LIB_FULL_NAME}")
    endif()
    set(CARGOKIT_TEMP_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargokit_build")
    # MSBuild 的 FileTracker 不支持超过 260 字符的路径，而 Flutter 的构建目录本身就很深，
    # 再叠加依赖内部的 CMake 中间产物（如 opusic-sys 的 TryCompile）就会超限。
    # 因此在 Windows 下默认把 cargokit 的构建中间目录挪到更短的用户目录，
    # 也可用环境变量 CARGOKIT_TEMP_DIR_OVERRIDE 显式指定。
    if (DEFINED ENV{CARGOKIT_TEMP_DIR_OVERRIDE} AND NOT "$ENV{CARGOKIT_TEMP_DIR_OVERRIDE}" STREQUAL "")
        file(TO_CMAKE_PATH "$ENV{CARGOKIT_TEMP_DIR_OVERRIDE}" CARGOKIT_TEMP_DIR)
    elseif (WIN32 AND DEFINED ENV{USERPROFILE})
        file(TO_CMAKE_PATH "$ENV{USERPROFILE}" _cargokit_user_home)
        set(CARGOKIT_TEMP_DIR "${_cargokit_user_home}/fn-audio-build/${CARGOKIT_LIB_NAME}")
    endif()

    if (FLUTTER_TARGET_PLATFORM)
        set(CARGOKIT_TARGET_PLATFORM "${FLUTTER_TARGET_PLATFORM}")
    else()
        set(CARGOKIT_TARGET_PLATFORM "windows-x64")
    endif()

    set(CARGOKIT_ENV
        "CARGOKIT_CMAKE=${CMAKE_COMMAND}"
        "CARGOKIT_CONFIGURATION=$<CONFIG>"
        "CARGOKIT_MANIFEST_DIR=${CMAKE_CURRENT_SOURCE_DIR}/${manifest_dir}"
        "CARGOKIT_TARGET_TEMP_DIR=${CARGOKIT_TEMP_DIR}"
        "CARGOKIT_OUTPUT_DIR=${CARGOKIT_OUTPUT_DIR}"
        "CARGOKIT_TARGET_PLATFORM=${CARGOKIT_TARGET_PLATFORM}"
        "CARGOKIT_TOOL_TEMP_DIR=${CARGOKIT_TEMP_DIR}/tool"
        "CARGOKIT_ROOT_PROJECT_DIR=${CMAKE_SOURCE_DIR}"
    )

    if (WIN32)
        # cargo 以插件外的临时目录为工作目录运行，读不到仓库根的 .cargo/config.toml，
        # 于是依赖里的 cmake crate 会自己猜生成器（本机猜成「VS 18 2026」，而实际
        # cmake 是 VS 2022 自带的 3.26，直接报 could not create named generator）。
        # 这里把外层 Flutter 构建用的 cmake 与生成器透传下去，保证内外一致。
        list(APPEND CARGOKIT_ENV
            "CMAKE=${CMAKE_COMMAND}"
            "CMAKE_GENERATOR=${CMAKE_GENERATOR}"
        )
    endif()

    if (WIN32)
        set(SCRIPT_EXTENSION ".cmd")
        set(IMPORT_LIB_EXTENSION ".lib")
    else()
        set(SCRIPT_EXTENSION ".sh")
        set(IMPORT_LIB_EXTENSION "")
        execute_process(COMMAND chmod +x "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}")
    endif()

    # Using generators in custom command is only supported in CMake 3.20+
    if (CMAKE_CONFIGURATION_TYPES AND ${CMAKE_VERSION} VERSION_LESS "3.20.0")
        foreach(CONFIG IN LISTS CMAKE_CONFIGURATION_TYPES)
            add_custom_command(
                OUTPUT
                "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG}/${CARGOKIT_LIB_FULL_NAME}"
                "${CMAKE_CURRENT_BINARY_DIR}/_phony_"
                COMMAND ${CMAKE_COMMAND} -E env ${CARGOKIT_ENV}
                "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}" build-cmake
                VERBATIM
            )
        endforeach()
    else()
        add_custom_command(
            OUTPUT
            ${OUTPUT_LIB}
            "${CMAKE_CURRENT_BINARY_DIR}/_phony_"
            COMMAND ${CMAKE_COMMAND} -E env ${CARGOKIT_ENV}
            "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}" build-cmake
            VERBATIM
        )
    endif()


    set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/_phony_" PROPERTIES SYMBOLIC TRUE)

    if (TARGET ${target})
        # If we have actual cmake target provided create target and make existing
        # target depend on it
        add_custom_target("${target}_cargokit" DEPENDS ${OUTPUT_LIB})
        add_dependencies("${target}" "${target}_cargokit")
        target_link_libraries("${target}" PRIVATE "${OUTPUT_LIB}${IMPORT_LIB_EXTENSION}")
        if(WIN32)
            target_link_options(${target} PRIVATE "/INCLUDE:${any_symbol_name}")
        endif()
    else()
        # Otherwise (FFI) just use ALL to force building always
        add_custom_target("${target}_cargokit" ALL DEPENDS ${OUTPUT_LIB})
    endif()

    # Allow adding the output library to plugin bundled libraries
    set("${target}_cargokit_lib" ${OUTPUT_LIB} PARENT_SCOPE)

endfunction()
