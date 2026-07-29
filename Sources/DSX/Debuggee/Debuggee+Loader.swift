// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Loader: Sendable {
    internal enum State: UInt8, Sendable {
      case absent = 0x00
      case loaded = 0x10
      case aborted = 0x20
      case ready = 0x30
      case initializing = 0x40
      case running = 0x50
      case terminated = 0x60
    }

    internal let value: UInt8

    internal var state: State? {
      State(rawValue: value)
    }

    internal init(value: UInt8) {
      self.value = value
    }
  }
}
