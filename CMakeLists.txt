# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 4.4)
project(DebugServerX LANGUAGES C Swift)

include(CTest)
if(BUILD_TESTING AND CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR "Tests require reflection (use a separate build tree)")
endif()
include(GNUInstallDirs)
include(cmake/Dependencies.cmake)

set(DSX_CODEGEN_EXECUTABLE "" CACHE FILEPATH "Native cross-build generator")

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
# Type-check each module once. Debug retains symbols and reflection.
set(CMAKE_Swift_COMPILATION_MODE wholemodule)
set(CMAKE_Swift_LANGUAGE_VERSION 6)
set(CMAKE_Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules")

if(WIN32)
  # Swift 6.2+ autolinks static Swift modules as lib<module>.lib.
  set(CMAKE_STATIC_LIBRARY_PREFIX_Swift lib)
endif()
if(CMAKE_HOST_WIN32)
  # The source list exceeds CreateProcess's command-line limit.
  set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON)
endif()

add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-explicit-module-build>")

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:-O2>"
    "$<$<COMPILE_LANGUAGE:Swift>:-Osize>"
    "$<$<COMPILE_LANGUAGE:Swift>:-gnone>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xfrontend -enable-single-module-llvm-emission>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xfrontend -disable-incremental-llvm-codegen>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xfrontend -disable-reflection-metadata>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xfrontend -disable-reflection-names>")
  if(WIN32)
    add_link_options("LINKER:/Brepro")
  elseif(APPLE)
    add_link_options("LINKER:-dead_strip")
  else()
    add_link_options("LINKER:--gc-sections")
  endif()
elseif(CMAKE_BUILD_TYPE STREQUAL "Debug" AND (ANDROID OR LINUX))
  # Swift 6.4 stalls in -Onone async debug-info propagation on these targets.
  # Preserve the existing optimized test build, with symbols and reflection.
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-O>")
endif()

if(ANDROID AND (NOT DSX_CODEGEN_EXECUTABLE OR BUILD_TESTING))
  dsx_fetch(Yams ASN1 Crypto)
elseif(ANDROID)
  dsx_fetch(ASN1 Crypto)
elseif(NOT DSX_CODEGEN_EXECUTABLE OR BUILD_TESTING)
  dsx_fetch(Yams)
endif()

if(TARGET Yams)
  # Serialized Yams imports CYaml, including during explicit module scanning.
  target_link_libraries(Yams PUBLIC
    CYaml)
  if(WIN32)
    target_compile_definitions(CYaml PRIVATE
      _CRT_NONSTDC_NO_WARNINGS)
  endif()
endif()

add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
                    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature InternalImportsByDefault>")
add_compile_definitions("$<$<COMPILE_LANGUAGE:Swift>:SWIFT_PACKAGE>")

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  if(WIN32)
    add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-debug-info-format=codeview>")
  else()
    add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-debug-info-format=dwarf>")
  endif()
endif()

if(BUILD_TESTING)
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
  include(cmake/Testing.cmake)
endif()

add_subdirectory(Sources)
add_subdirectory(Definitions)
install(TARGETS DSX DebugServerX)
if(BUILD_TESTING)
  add_subdirectory(Tests)
endif()
