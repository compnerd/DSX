// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

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
      var end = index
      while end < bytes.count, bytes[end] != UInt8(ascii: "\n") {
        end += 1
      }
      let map = read(until: end)
      index = end < bytes.count ? end + 1 : end
      if let map {
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

  @_lifetime(copy self)
  internal func path(_ map: borrowing LinuxMemoryMap) -> Span<UInt8>? {
    guard let path = map.path else {
      return nil
    }
    return bytes.extracting(path)
  }

  private mutating func read(until limit: Int) -> LinuxMemoryMap? {
    guard let start = hex(until: limit),
        consume(UInt8(ascii: "-"), until: limit),
        let end = hex(until: limit) else {
      return nil
    }
    spaces(until: limit)
    guard limit - index >= 4 else {
      return nil
    }
    let readable = bytes[index] == UInt8(ascii: "r")
    let writable = bytes[index + 1] == UInt8(ascii: "w")
    let executable = bytes[index + 2] == UInt8(ascii: "x")
    let shared = bytes[index + 3] == UInt8(ascii: "s")
    index += 4
    spaces(until: limit)
    guard let offset = hex(until: limit),
        field(until: limit), field(until: limit) else {
      return nil
    }
    spaces(until: limit)
    let path: Range<Int>? = index < limit ? index ..< limit : nil
    return LinuxMemoryMap(start: Debuggee.Address(rawValue: start),
                          end: Debuggee.Address(rawValue: end), offset: offset,
                          path: path, readable: readable, writable: writable,
                          executable: executable, shared: shared)
  }

  private mutating func consume(_ byte: UInt8, until limit: Int) -> Bool {
    guard index < limit, bytes[index] == byte else {
      return false
    }
    index += 1
    return true
  }

  private mutating func field(until limit: Int) -> Bool {
    spaces(until: limit)
    let start = index
    while index < limit, bytes[index] != UInt8(ascii: " ") {
      index += 1
    }
    return index > start
  }

  private mutating func spaces(until limit: Int) {
    while index < limit, bytes[index] == UInt8(ascii: " ") {
      index += 1
    }
  }

  private mutating func hex(until limit: Int) -> UInt64? {
    var value: UInt64 = 0
    let start = index
    while index < limit, let digit = UInt8(hex: bytes[index]) {
      guard value <= (UInt64.max - UInt64(digit)) / 16 else {
        return nil
      }
      value = value * 16 + UInt64(digit)
      index += 1
    }
    return index > start ? value : nil
  }
}
