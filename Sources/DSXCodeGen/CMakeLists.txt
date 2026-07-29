# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 4.4)
project(DSXCodeGen LANGUAGES C Swift)

if(PROJECT_IS_TOP_LEVEL)
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)
  set(CMAKE_Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules")
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib")
  set(CMAKE_Swift_LANGUAGE_VERSION 6)
  set(CMAKE_Swift_COMPILATION_MODE wholemodule)
  if(WIN32)
    set(CMAKE_STATIC_LIBRARY_PREFIX_Swift lib)
  endif()
  if(CMAKE_HOST_WIN32)
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
  elseif(CMAKE_BUILD_TYPE STREQUAL "Debug" AND (ANDROID OR LINUX))
    # Avoid Swift 6.4's -Onone async debug-info propagation stall.
    add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-O>")
  endif()
  include(../../cmake/Dependencies.cmake)
  dsx_fetch(Yams)
  target_link_libraries(Yams PUBLIC CYaml)
  if(WIN32)
    target_compile_definitions(CYaml PRIVATE _CRT_NONSTDC_NO_WARNINGS)
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
endif()

add_executable(DSXCodeGen
  DSXCodeGen.swift
  DSXCodeGenError.swift
  GeneratedSource.swift
  Packets/PacketDefinition.swift
  Packets/PacketGeneration.swift
  Registers/RegisterDefinition.swift
  Registers/RegisterDomains.swift
  Registers/RegisterGeneration.swift
  Registers/RegisterValidation.swift
  Schema.swift)

if(DSX_CODEGEN_EXECUTABLE)
  set_property(TARGET DSXCodeGen PROPERTY EXCLUDE_FROM_ALL ON)
endif()
target_link_libraries(DSXCodeGen PRIVATE Yams)
if(BUILD_TESTING AND NOT PROJECT_IS_TOP_LEVEL)
  dsx_testable(DSXCodeGen)
endif()
