// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBSignal {
  @inline(__always)
  internal static func `protocol`(_ signal: CInt,
                                  compatibility: CompatibilityMode) -> UInt8 {
    if compatibility == .lldb {
      UInt8(truncatingIfNeeded: signal)
    } else {
      SignalCatalog.gdb(signal)
    }
  }

  @inline(__always)
  internal static func native(_ signal: UInt64,
                              compatibility: CompatibilityMode) -> CInt? {
    guard signal <= UInt8.max else {
      return nil
    }
    return if compatibility == .lldb {
      CInt(signal)
    } else {
      SignalCatalog.native(signal)
    }
  }
}
