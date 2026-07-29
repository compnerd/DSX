// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct ModuleArchitectureTests {
  @Test(arguments: [("arm", "armv7"), ("arm", "armv7s"),
                    ("x86_64", "amd64"), ("i386", "i686"), ("i386", "x86"),
                    ("arm64", "aarch64"), ("aarch64", "arm64"),
                    ("arm64e", "arm64e"), ("riscv32", "riscv32")])
  internal func aliases(_ pair: (String, String)) {
    #expect(ModuleArchitecture.matches(pair.0, requested: pair.1))
  }

  @Test(arguments: [("arm64e", "arm64"), ("arm64", "arm64e"),
                    ("i386", "x86_64"), ("arm", "arm64"),
                    ("riscv32", "riscv64"), ("arm", "aarch64")])
  internal func distinctions(_ pair: (String, String)) {
    #expect(ModuleArchitecture.matches(pair.0, requested: pair.1) == false)
  }
}
