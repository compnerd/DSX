// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal struct LinuxMemoryMap: Sendable {
  internal let start: Debuggee.Address
  internal let end: Debuggee.Address
  internal let offset: UInt64
  internal let path: Range<Int>?
  internal let readable: Bool
  internal let writable: Bool
  internal let executable: Bool
  internal let shared: Bool
}

internal struct LinuxMemoryMapReader: ~Escapable {
  private let bytes: Span<UInt8>
  private var index: Int

  @_lifetime(copy bytes)
  internal init(_ bytes: consuming Span<UInt8>) {
    self.bytes = consume bytes
    index = 0
  }

  internal mutating func next() -> LinuxMemoryMap? {
    while index < bytes.count {
      let start = index
      while index < bytes.count, bytes[index] != UInt8(ascii: "\n") {
        index += 1
      }
      let line = bytes.extracting(start ..< index)
      if index < bytes.count {
        index += 1
      }
      if let map = parse(line, base: start) {
        return map
      }
    }
    return nil
  }

  internal func absolute(_ map: borrowing LinuxMemoryMap) -> Bool {
    guard let path = map.path else {
      return false
    }
    return bytes[path.lowerBound] == UInt8(ascii: "/")
  }

  internal func path(_ map: borrowing LinuxMemoryMap) -> String? {
    guard let path = map.path else {
      return nil
    }
    return bytes.extracting(path).withUnsafeBytes { bytes in
      String(decoding: bytes, as: UTF8.self)
    }
  }
}

private func parse(_ line: borrowing Span<UInt8>, base: Int)
    -> LinuxMemoryMap? {
  var index = 0
  guard let start = hex(line, index: &index),
      consume(UInt8(ascii: "-"), from: line, index: &index),
      let end = hex(line, index: &index) else {
    return nil
  }
  spaces(line, index: &index)
  guard index + 4 <= line.count else {
    return nil
  }
  let readable = line[index] == UInt8(ascii: "r")
  let writable = line[index + 1] == UInt8(ascii: "w")
  let executable = line[index + 2] == UInt8(ascii: "x")
  let shared = line[index + 3] == UInt8(ascii: "s")
  index += 4
  spaces(line, index: &index)
  guard let offset = hex(line, index: &index),
      field(line, index: &index), field(line, index: &index) else {
    return nil
  }
  spaces(line, index: &index)
  let path: Range<Int>? = if index < line.count {
    (base + index) ..< (base + line.count)
  } else {
    nil
  }
  return LinuxMemoryMap(start: Debuggee.Address(rawValue: start),
                        end: Debuggee.Address(rawValue: end), offset: offset,
                        path: path, readable: readable, writable: writable,
                        executable: executable, shared: shared)
}

private func consume(_ byte: UInt8, from bytes: borrowing Span<UInt8>,
                     index: inout Int) -> Bool {
  guard index < bytes.count, bytes[index] == byte else {
    return false
  }
  index += 1
  return true
}

private func field(_ bytes: borrowing Span<UInt8>, index: inout Int) -> Bool {
  spaces(bytes, index: &index)
  let start = index
  while index < bytes.count, bytes[index] != UInt8(ascii: " ") {
    index += 1
  }
  return index > start
}

private func spaces(_ bytes: borrowing Span<UInt8>, index: inout Int) {
  while index < bytes.count, bytes[index] == UInt8(ascii: " ") {
    index += 1
  }
}

private func hex(_ bytes: borrowing Span<UInt8>, index: inout Int) -> UInt64? {
  var value: UInt64 = 0
  let start = index
  while index < bytes.count, let digit = digit(bytes[index]) {
    guard value <= (UInt64.max - UInt64(digit)) / 16 else {
      return nil
    }
    value = value * 16 + UInt64(digit)
    index += 1
  }
  return index > start ? value : nil
}

private func digit(_ byte: UInt8) -> UInt8? {
  switch byte {
  case UInt8(ascii: "0") ... UInt8(ascii: "9"):
    byte - UInt8(ascii: "0")
  case UInt8(ascii: "A") ... UInt8(ascii: "F"):
    byte - UInt8(ascii: "A") + 10
  case UInt8(ascii: "a") ... UInt8(ascii: "f"):
    byte - UInt8(ascii: "a") + 10
  default:
    nil
  }
}

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

internal func decimal(_ value: borrowing Span<UInt8>) -> UInt64? {
  var result: UInt64 = 0
  var index = 0
  while index < value.count {
    let byte = value[index]
    guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
      break
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
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(Debuggee.Error) in
      let count = path.withCString { path in
        let raw = UnsafeMutableRawPointer(buffer.baseAddress!)
        let bytes = raw.assumingMemoryBound(to: CChar.self)
        return readlink(path, bytes, buffer.count)
      }
      guard count >= 0 else {
        throw failure(errno)
      }
      return String(decoding: UnsafeBufferPointer(start: buffer.baseAddress,
                                                  count: count), as: UTF8.self)
    })
  }

  internal static func failure(_ code: CInt) -> Debuggee.Error {
    if code == EFAULT {
      .memory
    } else {
      UnixError.debuggee(code, invalid: .process, support: true)
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
