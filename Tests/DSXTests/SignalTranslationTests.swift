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
        let wire = GDBSignal.protocol(CInt(signal), compatibility: mode)
        #expect(GDBSignal.native(UInt64(wire), compatibility: mode)
                == CInt(signal))
      }
    }
  }

#if os(FreeBSD) || os(OpenBSD)
  @Test
  internal func thread() {
    #expect(GDBSignal.native(37, compatibility: .gdb) == 32)
    #expect(GDBSignal.native(32, compatibility: .lldb) == 32)
    #expect(GDBSignal.native(32, compatibility: .gdb) == nil)
  }
#endif

#if os(FreeBSD)
  @Test
  internal func realtime() {
    #expect(GDBSignal.native(151, compatibility: .gdb) == 33)
    #expect(GDBSignal.native(79, compatibility: .gdb) == 65)
    #expect(GDBSignal.native(140, compatibility: .gdb) == 126)
    #expect(GDBSignal.native(141, compatibility: .gdb) == nil)
  }
#endif
}
