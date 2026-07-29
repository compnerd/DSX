// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct LogState: ~Copyable {
  internal var descriptor: CInt
  internal var owned: Bool
  internal var colour: Bool
  internal var buffer = Array<UInt8>()

  internal init(descriptor: CInt, owned: Bool, colour: Bool) {
    self.descriptor = descriptor
    self.owned = owned
    self.colour = colour
  }

  internal mutating func emit(_ level: LogLevel, _ channel: LogChannel,
                              _ message: borrowing String) -> Bool {
    begin(level, channel)
    buffer.append(contentsOf: message.utf8)
    return end()
  }

  internal mutating func emit(_ level: LogLevel, _ channel: LogChannel,
                              _ direction: LogDirection,
                              _ bytes: borrowing Span<UInt8>) -> Bool {
    begin(level, channel)
    if colour {
      append(direction.colour)
    }
    append(direction.symbol)
    if colour {
      reset()
    }
    buffer.append(0x20)
    guard bytes.count > 0 else {
      append("∅")
      return end()
    }
    buffer.append(0x22)
    for index in 0 ..< bytes.count {
      escape(bytes[index])
    }
    buffer.append(0x22)
    return end()
  }

  private mutating func begin(_ level: LogLevel, _ channel: LogChannel) {
    if colour {
      append(level.colour)
    }
    buffer.append(0x5b)
    append(level.label)
    buffer.append(0x5d)
    if colour {
      reset()
      buffer.append(0x20)
      append("\u{001b}[36m")
    } else {
      buffer.append(0x20)
    }
    buffer.append(0x5b)
    append(channel.label)
    buffer.append(contentsOf: "] ".utf8)
    if colour {
      reset()
    }
  }

  private mutating func end() -> Bool {
    buffer.append(0x0a)
    let written = buffer.withUnsafeBytes { bytes in
      LogSystem.write(descriptor, bytes)
    }
    buffer.removeAll(keepingCapacity: buffer.count > buffer.capacity / 4)
    return written
  }

  private mutating func append(_ value: StaticString) {
    value.withUTF8Buffer { bytes in
      buffer.append(contentsOf: bytes)
    }
  }

  private mutating func reset() {
    append("\u{001b}[0m")
  }

  private mutating func escape(_ byte: UInt8) {
    switch byte {
    case 0x00:
      append("\\0")
    case 0x09:
      append("\\t")
    case 0x0a:
      append("\\n")
    case 0x0d:
      append("\\r")
    case 0x22, 0x5c:
      buffer.append(0x5c)
      buffer.append(byte)
    case 0x20 ... 0x7e:
      buffer.append(byte)
    default:
      buffer.append(contentsOf: "\\x".utf8)
      buffer.append(hex(byte >> 4))
      buffer.append(hex(byte & 0x0f))
    }
  }
}

private func hex(_ value: UInt8) -> UInt8 {
  value < 10 ? value + 0x30 : value - 10 + 0x61
}
