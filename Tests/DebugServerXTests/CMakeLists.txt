# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

add_executable(DebugServerXTests
  CommandTests.swift
  ConnectionTests.swift)

target_link_libraries(DebugServerXTests PRIVATE DebugServerXTesting)
dsx_test(DebugServerXTests)
