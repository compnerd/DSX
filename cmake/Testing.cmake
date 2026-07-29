# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

# Expose executable internals to tests without linking two main entry points.
# Called in the executable's directory so its relative sources retain ownership.
function(dsx_testable module)
  get_target_property(sources ${module} SOURCES)
  get_target_property(dependencies ${module} LINK_LIBRARIES)
  add_library(${module}Testing STATIC ${sources})
  set_target_properties(${module}Testing PROPERTIES
    Swift_MODULE_NAME ${module}
    Swift_MODULE_DIRECTORY "${PROJECT_BINARY_DIR}/testing/${module}")
  target_include_directories(${module}Testing INTERFACE
    "${PROJECT_BINARY_DIR}/testing/${module}")
  target_compile_options(${module}Testing PRIVATE
    "SHELL:-Xfrontend -entry-point-function-name -Xfrontend ${module}_main")
  target_link_libraries(${module}Testing PUBLIC ${dependencies})
endfunction()
