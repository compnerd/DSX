# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

add_executable(DebugServerX
  Connection+Parsing.swift
  DSXAliases.swift
  DebugServerX.swift
  GDBServerCommand.swift
  PlatformServerCommand.swift
  Version.swift)

set_target_properties(DebugServerX PROPERTIES
  OUTPUT_NAME dsx)
target_link_libraries(DebugServerX PRIVATE
  DSXCore
  DSXArguments)

if(WIN32)
  # Never let the executable's import library overwrite the embedding library.
  set_property(TARGET DebugServerX PROPERTY
    ARCHIVE_OUTPUT_NAME dsx-executable)
endif()
if(BUILD_TESTING)
  dsx_testable(DebugServerX)
endif()
