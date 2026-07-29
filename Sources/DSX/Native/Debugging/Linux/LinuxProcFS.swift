// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal func decimal(_ value: UnsafePointer<CChar>) -> UInt64? {
  var result: UInt64 = 0
  var index = 0
  while value[index] != 0 {
    let byte = UInt8(bitPattern: value[index])
    guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
      return nil
    }
    let digit = UInt64(byte - UInt8(ascii: "0"))
    guard result <= (UInt64.max - digit) / 10 else {
      return nil
    }
    result = result * 10 + digit
    index += 1
  }
  return index > 0 ? result : nil
}

internal enum LinuxProcFS {
  private typealias Failure = Debuggee.Error

  private static let capacity = 4096

  internal static func contents(_ path: String) throws(Debuggee.Error)
      -> Array<UInt8> {
    let handle = try open(path)
    defer {
      _ = DSX::close(handle)
    }
    var bytes = Array<UInt8>()
    var offset: UInt64 = 0
    var count: Int
    repeat {
      count = 0
      try bytes.append(addingCapacity: capacity) { span throws(Failure) in
        try span.withUnsafeMutableBufferPointer { data, index throws(Failure) in
          guard let base = data.baseAddress else {
            throw .system(ENOMEM)
          }
          guard offset <= UInt64(off_t.max) else {
            throw .system(EOVERFLOW)
          }
          var result: Int
          repeat {
            result = pread(handle, base, data.count, off_t(offset))
          } while result == -1 && errno == EINTR
          guard result >= 0 else {
            throw failure(errno)
          }
          index += result
          count = result
        }
      }
      offset += UInt64(count)
    } while count > 0
    return bytes
  }

  internal static func read(_ path: String,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let handle = try open(path)
    defer {
      _ = DSX::close(handle)
    }
    try output.withUnsafeMutableBufferPointer { bytes, index throws(Failure) in
      let base = bytes.baseAddress?.advanced(by: index)
      var length: Int
      repeat {
        length = DSX::read(handle, base, bytes.count - index)
      } while length == -1 && errno == EINTR
      guard length >= 0 else {
        throw failure(errno)
      }
      index += length
    }
  }

  internal static func read(_ path: String, offset: UInt64, limit: Int,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    guard offset <= UInt64(off_t.max) else {
      throw .system(EOVERFLOW)
    }
    let handle = try open(path)
    defer {
      _ = DSX::close(handle)
    }
    return try output
      .withUnsafeMutableBufferPointer { bytes, index throws(Debuggee.Error) in
      let requested = min(limit, bytes.count - index)
      let base = bytes.baseAddress!.advanced(by: index)
      var count: Int
      repeat {
        count = pread(handle, base, requested, off_t(offset))
      } while count == -1 && errno == EINTR
      guard count >= 0 else {
        throw failure(errno)
      }
      index += count
      guard count == requested else {
        return .last
      }
      let (next, overflow) = offset.addingReportingOverflow(UInt64(count))
      if overflow {
        throw .system(EOVERFLOW)
      }
      guard next <= UInt64(off_t.max) else {
        throw .system(EOVERFLOW)
      }
      var byte: UInt8 = 0
      var remaining: Int
      repeat {
        remaining = pread(handle, &byte, 1, off_t(next))
      } while remaining == -1 && errno == EINTR
      guard remaining >= 0 else {
        throw failure(errno)
      }
      return remaining > 0 ? .more : .last
    }
  }

  internal static func link(_ path: String) throws(Debuggee.Error) -> String {
    var capacity = capacity
    while true {
      let value = try withUnsafeTemporaryAllocation(of: UInt8.self,
                                                    capacity: capacity,
                                                    { buffer throws(Failure) in
        let count = path.withCString { path in
          let raw = UnsafeMutableRawPointer(buffer.baseAddress!)
          let bytes = raw.assumingMemoryBound(to: CChar.self)
          return readlink(path, bytes, buffer.count)
        }
        guard count >= 0 else {
          throw failure(errno)
        }
        guard count < buffer.count else {
          return nil as String?
        }
        let bytes = UnsafeBufferPointer(start: buffer.baseAddress, count: count)
        return String(decoding: bytes, as: UTF8.self)
      })
      if let value {
        return value
      }
      guard capacity <= Int.max / 2 else {
        throw .system(EOVERFLOW)
      }
      capacity *= 2
    }
  }

  internal static func failure(_ code: CInt) -> Debuggee.Error {
    if code == EFAULT {
      .memory
    } else {
      Debuggee.Error(unix: code, invalid: .process, support: true)
    }
  }

  private static func open(_ path: String) throws(Debuggee.Error) -> CInt {
    let handle = path.withCString { path in
      DSX::open(path, O_RDONLY | O_CLOEXEC)
    }
    guard handle >= 0 else {
      throw failure(errno)
    }
    return handle
  }
}
#endif
