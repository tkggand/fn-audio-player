cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "fn_audio_engine")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust fn_audio_engine "")

# 由 cargokit 构建出的 DLL 交给 Flutter 打包。
set(fn_audio_engine_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
