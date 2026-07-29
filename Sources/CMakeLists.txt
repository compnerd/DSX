# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

if(NOT DSX_CODEGEN_EXECUTABLE OR BUILD_TESTING)
  add_subdirectory(DSXCodeGen)
endif()
add_subdirectory(DSXShims)
add_subdirectory(DSX)
add_subdirectory(DSXArguments)
add_subdirectory(DebugServerX)
