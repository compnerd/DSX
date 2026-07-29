// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct SignalTranslationTests {
  @Test
  internal func roundtrip() {
    SignalCatalog.visit { signal in
      for mode in [CompatibilityMode.gdb, .lldb] {
        let wire = mode.signal(CInt(signal))
        #expect(mode.native(UInt64(wire)) == CInt(signal))
      }
    }
  }

#if os(FreeBSD) || os(OpenBSD)
  @Test
  internal func thread() {
    #expect(CompatibilityMode.gdb.native(37) == 32)
    #expect(CompatibilityMode.lldb.native(32) == 32)
    #expect(CompatibilityMode.gdb.native(32) == nil)
  }
#endif

#if os(FreeBSD)
  @Test
  internal func realtime() {
    #expect(CompatibilityMode.gdb.native(151) == 33)
    #expect(CompatibilityMode.gdb.native(79) == 65)
    #expect(CompatibilityMode.gdb.native(140) == 126)
    #expect(CompatibilityMode.gdb.native(141) == nil)
  }
#endif
}
