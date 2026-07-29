# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

include_guard(GLOBAL)

find_program(CMAKE_Swift_COMPILER swiftc REQUIRED)
if(NOT DSX_TARGET_TRIPLE)
  execute_process(COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
    OUTPUT_VARIABLE information COMMAND_ERROR_IS_FATAL ANY)
  string(JSON triple GET "${information}" target triple)
  set(DSX_TARGET_TRIPLE "${triple}" CACHE STRING "Target triple")
endif()
get_filename_component(tools "${CMAKE_Swift_COMPILER}" DIRECTORY)
if(CMAKE_HOST_APPLE)
  execute_process(COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
    OUTPUT_VARIABLE information COMMAND_ERROR_IS_FATAL ANY)
  string(JSON resources GET "${information}" paths runtimeResourcePath)
  get_filename_component(tools "${resources}/../../bin" ABSOLUTE)
endif()
find_program(CMAKE_C_COMPILER clang PATHS "${tools}" NO_DEFAULT_PATH REQUIRED)
find_program(CMAKE_CXX_COMPILER clang++ PATHS "${tools}"
  NO_DEFAULT_PATH REQUIRED)
set(CMAKE_Swift_COMPILER_TARGET "${DSX_TARGET_TRIPLE}")
set(CMAKE_C_COMPILER_TARGET "${DSX_TARGET_TRIPLE}")
set(CMAKE_CXX_COMPILER_TARGET "${DSX_TARGET_TRIPLE}")
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  DSX_TARGET_TRIPLE DSX_ANDROID_SDK_JSON)

if(DSX_TARGET_TRIPLE MATCHES "-apple-")
  set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Minimum Apple OS version")
  if(NOT CMAKE_OSX_SYSROOT)
    execute_process(COMMAND xcrun --sdk macosx --show-sdk-path
      OUTPUT_VARIABLE sdk OUTPUT_STRIP_TRAILING_WHITESPACE
      COMMAND_ERROR_IS_FATAL ANY)
    set(CMAKE_OSX_SYSROOT "${sdk}" CACHE PATH "Apple SDK")
  endif()
elseif(DSX_TARGET_TRIPLE MATCHES "-windows-")
  set(CMAKE_SYSTEM_NAME Windows)
  string(REGEX REPLACE "-.*" "" CMAKE_SYSTEM_PROCESSOR "${DSX_TARGET_TRIPLE}")
  set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
elseif(DSX_TARGET_TRIPLE MATCHES "-android([0-9]+)$")
  set(CMAKE_SYSTEM_NAME Android)
  set(CMAKE_SYSTEM_VERSION "${CMAKE_MATCH_1}")
  set(CMAKE_USER_MAKE_RULES_OVERRIDE
    "${CMAKE_CURRENT_LIST_DIR}/../Android.cmake")
  file(TO_CMAKE_PATH "$ENV{ANDROID_NDK_HOME}" CMAKE_ANDROID_NDK)
  set(CMAKE_ANDROID_STL_TYPE c++_static)
  set(CMAKE_LINKER_TYPE LLD)
  set(CMAKE_Swift_USING_LINKER_LLD -use-ld=lld)
  file(GLOB prebuilt LIST_DIRECTORIES TRUE
    "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/*")
  list(LENGTH prebuilt count)
  if(NOT count EQUAL 1)
    message(FATAL_ERROR "Expected one host toolchain in the NDK")
  endif()
  set(CMAKE_SYSROOT "${prebuilt}/sysroot")
  if(DSX_TARGET_TRIPLE MATCHES "^aarch64-")
    set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
  elseif(DSX_TARGET_TRIPLE MATCHES "^armv7-")
    set(CMAKE_ANDROID_ARCH_ABI armeabi-v7a)
    set(CMAKE_C_COMPILER_TARGET "armv7-none-linux-androideabi28")
    set(CMAKE_CXX_COMPILER_TARGET "${CMAKE_C_COMPILER_TARGET}")
  elseif(DSX_TARGET_TRIPLE MATCHES "^i686-")
    set(CMAKE_ANDROID_ARCH_ABI x86)
  else()
    set(CMAKE_ANDROID_ARCH_ABI x86_64)
  endif()
  file(READ "${DSX_ANDROID_SDK_JSON}" metadata)
  get_filename_component(directory "${DSX_ANDROID_SDK_JSON}" DIRECTORY)
  string(JSON sdk GET "${metadata}" targetTriples "${DSX_TARGET_TRIPLE}")
  string(JSON sysroot GET "${sdk}" sdkRootPath)
  string(JSON resources GET "${sdk}" swiftStaticResourcesPath)
  execute_process(COMMAND "${CMAKE_C_COMPILER}" -print-resource-dir
    OUTPUT_VARIABLE clang OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
  file(TO_CMAKE_PATH "${sysroot}" sysroot)
  file(TO_CMAKE_PATH "${resources}" resources)
  cmake_path(ABSOLUTE_PATH sysroot BASE_DIRECTORY "${directory}" NORMALIZE)
  cmake_path(ABSOLUTE_PATH resources BASE_DIRECTORY "${directory}" NORMALIZE)
  file(TO_CMAKE_PATH "${clang}" clang)
  # The NDK sysroot contains no Swift startup object. Select it from the
  # separate Swift runtime instead of the driver's SDK-relative default.
  string(REGEX MATCH "^[^-]+" architecture "${DSX_TARGET_TRIPLE}")
  string(APPEND CMAKE_Swift_LINK_FLAGS
    " -nostartfiles \"${resources}/android/${architecture}/swiftrt.o\"")
  file(GLOB builtins LIST_DIRECTORIES TRUE "${prebuilt}/lib/clang/*")
  list(LENGTH builtins count)
  if(NOT count EQUAL 1)
    message(FATAL_ERROR "Expected one Clang resource directory in the NDK")
  endif()
  # Use this Clang's headers and the NDK's target runtime at link time.
  set(CMAKE_C_USING_LINKER_LLD -fuse-ld=lld -resource-dir "${builtins}")
  set(CMAKE_CXX_USING_LINKER_LLD "${CMAKE_C_USING_LINKER_LLD}")
  string(APPEND CMAKE_Swift_FLAGS_INIT
    # CMake's Swift driver detection omits CMAKE_Swift_COMPILER_TARGET.
    " -target ${DSX_TARGET_TRIPLE} -static-stdlib -sdk \"${sysroot}\" "
    "-resource-dir \"${resources}\" "
    "-Xcc -resource-dir -Xcc \"${clang}\" "
    "-Xclang-linker -resource-dir -Xclang-linker \"${builtins}\"")
  foreach(entry IN ITEMS includeSearchPaths librarySearchPaths)
    string(JSON count ERROR_VARIABLE error LENGTH "${sdk}" "${entry}")
    if(NOT error AND count GREATER 0)
      if(entry STREQUAL "includeSearchPaths")
        set(flag -I)
      else()
        set(flag -L)
      endif()
      math(EXPR last "${count} - 1")
      foreach(index RANGE ${last})
        string(JSON path GET "${sdk}" "${entry}" ${index})
        file(TO_CMAKE_PATH "${path}" path)
        cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${directory}" NORMALIZE)
        string(APPEND CMAKE_Swift_FLAGS_INIT " ${flag} \"${path}\"")
      endforeach()
    endif()
  endforeach()
endif()
