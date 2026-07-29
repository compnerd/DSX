# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

if(APPLE)
  execute_process(COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
    OUTPUT_VARIABLE information COMMAND_ERROR_IS_FATAL ANY)
  string(JSON resources GET "${information}" paths runtimeResourcePath)
  set(testing "${resources}/macosx/testing")
  include_directories("${testing}")
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-plugin-path '${resources}/host/plugins/testing'>")
  link_directories("${testing}")
  list(APPEND CMAKE_BUILD_RPATH "${testing}")
elseif(WIN32)
  get_filename_component(developer "$ENV{SDKROOT}/../.." ABSOLUTE)
  file(GLOB installations "${developer}/Library/Testing-*")
  find_path(DSX_TESTING_PATH usr/lib/swift/windows/Testing.swiftmodule
    PATHS ${installations} REQUIRED NO_DEFAULT_PATH)
  set(testing "${DSX_TESTING_PATH}/usr/lib/swift/windows")
  if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(runtime "${DSX_TESTING_PATH}/usr/bin64a")
  elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
    set(runtime "${DSX_TESTING_PATH}/usr/bin64")
  else()
    set(runtime "${DSX_TESTING_PATH}/usr/bin32")
  endif()
  get_filename_component(tools "${CMAKE_Swift_COMPILER}" DIRECTORY)
  include_directories("${testing}")
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-load-plugin-library '${tools}/TestingMacros.dll'>")
  link_directories("${testing}/${CMAKE_SYSTEM_PROCESSOR}")
endif()

function(dsx_test target)
  target_sources(${target} PRIVATE "${PROJECT_SOURCE_DIR}/cmake/Testing.swift")
  if(APPLE)
    # Native debugging tests launch a stopped copy of their own executable.
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND /usr/bin/codesign --force --sign -
        --entitlements "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Entitlements.plist"
        "$<TARGET_FILE:${target}>"
      VERBATIM)
  endif()
  add_test(NAME ${target} COMMAND ${target} --no-parallel)
  set_tests_properties(${target} PROPERTIES
    FAIL_REGULAR_EXPRESSION "Test run with 0 tests")
  if(WIN32)
    set_tests_properties(${target} PROPERTIES
      ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${runtime}")
  endif()
endfunction()

add_subdirectory(DSXTests)
add_subdirectory(DebugServerXTests)
add_subdirectory(DSXCodeGenTests)
