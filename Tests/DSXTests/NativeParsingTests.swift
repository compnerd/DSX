// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct NativeParsingTests {
  @Test
  internal func identifiers() {
    let valid = Array("123".utf8)
    let name = Array("123worker".utf8)
    let overflow = Array("18446744073709551616".utf8)
    #expect(decimal(valid.span) == 123)
    #expect(decimal(name.span) == nil)
    #expect(decimal(overflow.span) == nil)
  }

  @Test
  internal func paths() {
    let path = Array(#"/tmp/a\b.so"#.utf8)
#if os(Windows)
    let match = NativeFileSystem.matches(path.span, "b.so", component: true)
    #expect(match)
#else
    let match = NativeFileSystem.matches(path.span, #"a\b.so"#, component: true)
    let other = NativeFileSystem.matches(path.span, "b.so", component: true)
    #expect(match)
    #expect(other == false)
#endif
  }
}
