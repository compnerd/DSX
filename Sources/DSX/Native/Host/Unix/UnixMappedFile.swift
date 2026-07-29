// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

internal struct UnixMappedFile: ~Copyable {
  private let address: UnsafePointer<UInt8>
  internal let count: Int

  internal init(_ path: String) throws(Debuggee.Error) {
    let handle = try NativeFileSystem.open(path, options: [.read], mode: 0)
    defer {
      try? NativeFileSystem.close(handle)
    }
    let size = try NativeFileSystem.size(handle)
    guard size > 0, size <= UInt64(Int.max) else {
      throw .process
    }
    let count = Int(size)
    let mapping: UnsafeMutableRawPointer? =
        mmap(nil, count, PROT_READ, MAP_PRIVATE, handle, 0)
    if mapping == MAP_FAILED {
      throw UnixError.filesystem(errno)
    }
    guard let mapping else {
      throw UnixError.filesystem(errno)
    }
    address = UnsafeRawPointer(mapping).assumingMemoryBound(to: UInt8.self)
    self.count = count
  }

  deinit {
    _ = munmap(UnsafeMutableRawPointer(mutating: address), count)
  }

  @_lifetime(borrow self)
  internal borrowing func span() -> Span<UInt8> {
    Span(_unsafeStart: address, count: count)
  }
}
#endif
