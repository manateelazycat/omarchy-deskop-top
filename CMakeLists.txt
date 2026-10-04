# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 ManateeLazyCat

cmake_minimum_required(VERSION 3.21)
project(omarchy-desktop-top VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 REQUIRED COMPONENTS Quick Qml)
find_package(PkgConfig REQUIRED)
pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm>=0.3)
qt_standard_project_setup(REQUIRES 6.5)
qt_add_qml_module(desktop_top_terminal
    URI DesktopTop VERSION 1.0
    PLUGIN_TARGET desktop_top_terminal
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/DesktopTop"
    SOURCES native/Terminal.h native/Terminal.cpp)
target_link_libraries(desktop_top_terminal PRIVATE Qt6::Quick PkgConfig::VTERM util)
target_include_directories(desktop_top_terminal PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/native")
target_compile_options(desktop_top_terminal PRIVATE -Wall -Wextra -Wpedantic)
