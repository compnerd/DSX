// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct DebugCapabilities: Sendable {
  internal let bits: UInt16

  internal init(bits: UInt16 = 0) {
    self.bits = bits
  }

  internal static func | (lhs: DebugCapabilities,
                          rhs: DebugCapabilities) -> DebugCapabilities {
    DebugCapabilities(bits: lhs.bits | rhs.bits)
  }

  internal func contains(_ member: DebugCapabilities) -> Bool {
    bits & member.bits == member.bits
  }

  internal static let allocation = DebugCapabilities(bits: 1 << 0)
  internal static let auxiliary = DebugCapabilities(bits: 1 << 1)
  internal static let core = DebugCapabilities(bits: 1 << 12)
  internal static let threads = DebugCapabilities(bits: 1 << 13)
  internal static let syscalls = DebugCapabilities(bits: 1 << 14)
  internal static let images = DebugCapabilities(bits: 1 << 15)
  internal static let detachment = DebugCapabilities(bits: 1 << 2)
  internal static let executable = DebugCapabilities(bits: 1 << 3)
  internal static let fork = DebugCapabilities(bits: 1 << 4)
  internal static let libraries = DebugCapabilities(bits: 1 << 11)
  internal static let passthrough = DebugCapabilities(bits: 1 << 5)
  internal static let randomization = DebugCapabilities(bits: 1 << 6)
  internal static let signal = DebugCapabilities(bits: 1 << 7)
  internal static let svr4 = DebugCapabilities(bits: 1 << 8)
  internal static let tib = DebugCapabilities(bits: 1 << 9)
  internal static let vfork = DebugCapabilities(bits: 1 << 10)
}

extension DebugCapabilities {
  internal static var current: DebugCapabilities {
    NativeDebugControl.capabilities | CoreDump.capabilities
  }
}
