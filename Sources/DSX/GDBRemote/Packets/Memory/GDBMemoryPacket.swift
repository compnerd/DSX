// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBMemoryPacket {
  internal static func read(_ payload: borrowing Span<UInt8>,
                            session: borrowing DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested = try reader.length()
    let process =
        try GDBPacketScope.process(state.selection.general,
                                   debuggee: session.debuggee)
    let limit = min(requested, writer.output.freeCapacity / 2)
    guard limit == requested else {
      throw .capacity
    }
    let start = writer.output.count
    try translate(NativeMemory.read(process, address: address, size: limit,
                                    into: &writer.output))
    session.breakpoints.restore(process, address: address, start: start,
                                output: &writer.output)
    let count = writer.output.count - start
    guard count <= limit, writer.output.freeCapacity >= count else {
      throw .capacity
    }
    for _ in 0 ..< count {
      writer.output.append(0x00)
    }
    var index = count
    while index > 0 {
      index -= 1
      let byte = writer.output[start + index]
      writer.output[start + index * 2] = GDBPacketWriter.hexadecimal(byte >> 4)
      writer.output[start + index * 2 + 1] = GDBPacketWriter.hexadecimal(byte)
    }
  }

  internal static func ranges(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let count = try rangecount(payload)
    let process =
        try GDBPacketScope.process(state.selection.general,
                                   debuggee: session.debuggee)
    try withUnsafeTemporaryAllocation(of: Int.self, capacity: count,
                                      { sizes throws(GDBHandlerError) in
      try withUnsafeTemporaryAllocation(of: UInt8.self,
                                        capacity: writer.output.freeCapacity,
                                        { buffer throws(GDBHandlerError) in
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        var reader = GDBPacketReader(payload.extracting(0...))
        for index in 0 ..< count {
          let address = try reader.address()
          let requested = try reader.hex()
          guard requested <= UInt64(output.freeCapacity) else {
            throw .capacity
          }
          let last = index + 1 == count
          let separated = if last {
            reader.consume(UInt8(ascii: ";")) ||
                reader.consume(UInt8(ascii: ",")) &&
                reader.consume(UInt8(ascii: ";"))
          } else {
            reader.consume(UInt8(ascii: ","))
          }
          guard separated else {
            throw .malformed
          }
          let start = output.count
          do throws(Debuggee.Error) {
            try NativeMemory.read(process, address: address,
                                  size: Int(requested), into: &output)
            session.breakpoints.restore(process, address: address, start: start,
                                        output: &output)
          } catch {
          }
          let size = output.count - start
          guard UInt64(size) <= requested else {
            throw .debuggee(.memory)
          }
          sizes[index] = size
        }
        guard reader.empty else {
          throw .malformed
        }
        var capacity = 1
        for index in 0 ..< count {
          capacity += digits(UInt64(sizes[index]))
          if index > 0 {
            capacity += 1
          }
        }
        guard capacity + output.count <= writer.output.freeCapacity else {
          throw .capacity
        }
        for index in 0 ..< count {
          if index > 0 {
            try writer.append(UInt8(ascii: ","))
          }
          try writer.hex(UInt64(sizes[index]))
        }
        try writer.append(UInt8(ascii: ";"))
        try writer.append(output.span)
      })
    })
  }
}

extension GDBMemoryPacket {
  internal static func search(_ payload: borrowing Span<UInt8>,
                              debuggee: borrowing Debuggee,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try Debuggee.Address(rawValue: reader.hex())
    guard reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let length = try reader.hex()
    guard reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let pattern = reader.remaining()
    guard !pattern.isEmpty else {
      throw .malformed
    }
    guard UInt64(pattern.count) <= length else {
      return try writer.append("0")
    }
    let process =
        try GDBPacketScope.process(state.selection.general, debuggee: debuggee)
    let result =
        try translate(NativeMemory.search(process, address: address,
                                          length: length, pattern: pattern))
    guard let result else {
      return try writer.append("0")
    }
    try writer.append("1,")
    try writer.hex(result.rawValue)
  }

  internal static func write(_ payload: borrowing Span<UInt8>,
                             debuggee: borrowing Debuggee,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested =
        try reader.length(delimiter: UInt8(ascii: ":"), maximum: Int.max / 2)
    guard reader.count == requested * 2 else {
      throw .malformed
    }
    try GDBPacketReader.decode(reader.remaining(), into: &writer.output)
    let process =
        try GDBPacketScope.process(state.selection.general, debuggee: debuggee)
    let count = try translate(writer.bytes { bytes throws(Debuggee.Error) in
      try NativeMemory.write(process, address: address, bytes: bytes)
    })
    guard count == requested else {
      throw .debuggee(.memory)
    }
    try writer.append("OK")
  }
}

internal enum GDBBinaryMemoryPacket {
  internal static func read(_ payload: borrowing Span<UInt8>,
                            session: borrowing DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let count = try reader.length()
    guard count <= writer.output.freeCapacity else {
      throw .capacity
    }
    let process =
        try GDBPacketScope.process(state.selection.general,
                                   debuggee: session.debuggee)
    let start = writer.output.count
    try translate(NativeMemory.read(process, address: address, size: count,
                                    into: &writer.output))
    session.breakpoints.restore(process, address: address, start: start,
                                output: &writer.output)
    guard writer.output.count - start <= count else {
      throw .debuggee(.memory)
    }
  }
}

extension GDBBinaryMemoryPacket {
  internal static func write(_ payload: borrowing Span<UInt8>,
                             debuggee: borrowing Debuggee,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested = try reader.length(delimiter: UInt8(ascii: ":"))
    let bytes = reader.remaining()
    guard bytes.count == requested else {
      throw .malformed
    }
    let process =
        try GDBPacketScope.process(state.selection.general, debuggee: debuggee)
    let count =
        try translate(NativeMemory.write(process, address: address,
                                         bytes: bytes))
    guard count == requested else {
      throw .debuggee(.memory)
    }
    try writer.append("OK")
  }
}

extension GDBMemoryPacket {
  internal static func region(_ payload: borrowing Span<UInt8>,
                              debuggee: borrowing Debuggee,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    if reader.empty {
      return try writer.append("OK")
    }
    let address = try Debuggee.Address(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    let process =
        try GDBPacketScope.process(state.selection.general, debuggee: debuggee)
    let region = try translate(NativeMemory.region(process, address: address))
    try writer.append("start:")
    try writer.hex(region.address.rawValue)
    try writer.append(";size:")
    try writer.hex(region.size)
    try writer.append(UInt8(ascii: ";"))
    if region.readable || region.writable || region.executable {
      try writer.append("permissions:")
      if region.readable {
        try writer.append(UInt8(ascii: "r"))
      }
      if region.writable {
        try writer.append(UInt8(ascii: "w"))
      }
      if region.executable {
        try writer.append(UInt8(ascii: "x"))
      }
      try writer.append(UInt8(ascii: ";"))
    }
    if let name = region.name {
      try writer.append("name:")
      try writer.encoded(name)
      try writer.append(UInt8(ascii: ";"))
    }
    if let kind = region.kind {
      try writer.append("type:")
      switch kind {
      case .heap(let allocation):
        try writer.append("heap")
        switch allocation {
        case .large: try writer.append(",malloc-large")
        case .small: try writer.append(",malloc-small")
        case .tiny: try writer.append(",malloc-tiny")
        case .unknown: break
        }
      case .malloc(let allocation):
        switch allocation {
        case .guarded: try writer.append("malloc-guard")
        case .metadata: try writer.append("malloc-metadata")
        case .reserved: try writer.append("malloc-reserved")
        }
      case .stack(let guarded):
        try writer.append(guarded ? "stack-guard" : "stack")
      }
      try writer.append(UInt8(ascii: ";"))
    }
  }
}

private func rangecount(_ payload: borrowing Span<UInt8>)
    throws(GDBHandlerError) -> Int {
  var reader = GDBPacketReader(payload.extracting(0...))
  var count = 0
  while reader.empty == false {
    _ = try reader.address()
    _ = try reader.hex()
    count += 1
    if reader.consume(UInt8(ascii: ";")) {
      guard reader.empty else {
        throw .malformed
      }
      return count
    }
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    if reader.consume(UInt8(ascii: ";")) {
      guard reader.empty else {
        throw .malformed
      }
      return count
    }
  }
  throw .malformed
}

extension GDBPacketReader {
  fileprivate mutating func address() throws(GDBHandlerError)
      -> Debuggee.Address {
    let address = try Debuggee.Address(rawValue: hex())
    guard consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    return address
  }

  fileprivate mutating func length(delimiter: UInt8? = nil,
                                   maximum: Int = Int.max)
      throws(GDBHandlerError) -> Int {
    let requested = try hex()
    let complete = if let delimiter {
      consume(delimiter)
    } else {
      empty
    }
    guard complete, requested <= UInt64(maximum) else {
      throw .malformed
    }
    return Int(requested)
  }
}

private func digits(_ value: UInt64) -> Int {
  var value = value
  var count = 1
  while value >= 16 {
    value /= 16
    count += 1
  }
  return count
}

private typealias ByteBody<Result> =
    (borrowing Span<UInt8>) throws(Debuggee.Error) -> Result

extension GDBPacketWriter {
  fileprivate mutating func bytes<Result>(_ body: ByteBody<Result>)
      throws(Debuggee.Error) -> Result {
    let result = try body(output.span)
    output.removeAll()
    return result
  }
}
