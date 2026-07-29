// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import WinSDK

extension WindowsContext {
  internal static func step(_ context: inout CONTEXT) {
    context.Cpsr |= kCPSRSoftwareStep
  }
}

extension WindowsRegisters {
  internal static func layout(_ register: RegisterIdentifier)
      throws(Debuggee.Error) -> (offset: Int, native: Int, size: Int) {
    switch register.rawValue {
    case 0 ... 30:
      (8 + Int(register.rawValue) * 8, 8, 8)
    case 31:
      (256, 8, 8)
    case 32:
      (264, 8, 8)
    case 33:
      (4, 4, 4)
    case 34 ... 65:
      (272 + Int(register.rawValue - 34) * 16, 16, 16)
    case 66:
      (788, 4, 4)
    case 67:
      (784, 4, 4)
    default:
      throw .register
    }
  }
}
#endif
