// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct MemoryPermissions: OptionSet, Sendable {
  internal let rawValue: UInt8

  internal static let read = MemoryPermissions(rawValue: 0x01)
  internal static let write = MemoryPermissions(rawValue: 0x02)
  internal static let execute = MemoryPermissions(rawValue: 0x04)
}

extension Debuggee {
  internal struct MemoryRegion: Sendable {
    internal enum Heap: Sendable {
      case large
      case small
      case tiny
      case unknown
    }

    internal enum AllocatorRegion: Sendable {
      case guarded
      case metadata
      case reserved
    }

    internal enum Kind: Sendable {
      case heap(Heap)
      case allocator(AllocatorRegion)
      case stack(Bool)
    }

    internal let address: Address
    internal let size: UInt64
    internal let readable: Bool
    internal let writable: Bool
    internal let executable: Bool
    internal let mapped: Bool
    internal let name: String?
    internal let kind: Kind?

    internal init(address: Address, size: UInt64, readable: Bool,
                  writable: Bool, executable: Bool, name: String? = nil,
                  kind: Kind? = nil, mapped: Bool = true) {
      self.address = address
      self.size = size
      self.readable = readable
      self.writable = writable
      self.executable = executable
      self.mapped = mapped
      self.name = name
      self.kind = kind
    }
  }
}
