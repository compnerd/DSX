# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

add_executable(DSXCodeGenTests DSXCodeGenTests.swift)

target_link_libraries(DSXCodeGenTests PRIVATE DSXCodeGenTesting)
dsx_test(DSXCodeGenTests)
