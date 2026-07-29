// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct MemoryRegion: Sendable {
    internal enum Heap: Sendable {
      case large
      case small
      case tiny
      case unknown
    }

    internal enum Malloc: Sendable {
      case guarded
      case metadata
      case reserved
    }

    internal enum Kind: Sendable {
      case heap(Heap)
      case malloc(Malloc)
      case stack(Bool)
    }

    internal let address: Address
    internal let size: UInt64
    internal let readable: Bool
    internal let writable: Bool
    internal let executable: Bool
    internal let name: String?
    internal let kind: Kind?

    internal init(address: Address, size: UInt64, readable: Bool,
                  writable: Bool, executable: Bool, name: String? = nil,
                  kind: Kind? = nil) {
      self.address = address
      self.size = size
      self.readable = readable
      self.writable = writable
      self.executable = executable
      self.name = name
      self.kind = kind
    }
  }
}
