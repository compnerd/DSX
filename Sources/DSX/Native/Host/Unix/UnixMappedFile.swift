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
  private let count: Int

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
    // Own the bytes: truncating a file-backed mapping can fault during parsing.
    let mapping: UnsafeMutableRawPointer? =
        mmap(nil, count, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
    if mapping == MAP_FAILED {
      throw Debuggee.Error(filesystem: errno)
    }
    guard let mapping else {
      throw Debuggee.Error(filesystem: errno)
    }
    do throws(Debuggee.Error) {
      let bytes = mapping.bindMemory(to: UInt8.self, capacity: count)
      let buffer = UnsafeMutableBufferPointer(start: bytes, count: count)
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      while output.count < count {
        let offset = output.count
        try NativeFileSystem.read(handle, offset: UInt64(offset),
                                  size: count - offset, into: &output)
        guard output.count > offset else {
          throw .process
        }
      }
    } catch {
      _ = munmap(mapping, count)
      throw error
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
