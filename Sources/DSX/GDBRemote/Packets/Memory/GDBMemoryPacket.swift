// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func read(memory payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested = try reader.length()
    let process = try state.selection.general.process(in: debuggee)
    let limit = min(requested, writer.output.freeCapacity / 2)
    guard limit == requested else {
      throw .capacity
    }
    let start = writer.output.count
    try translate(read(process, address: address, size: limit,
                       into: &writer.output))
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
      writer.output[start + index * 2] = (byte >> 4).hexadecimal
      writer.output[start + index * 2 + 1] = byte.hexadecimal
    }
  }

  internal borrowing func ranges(_ payload: borrowing Span<UInt8>,
                                 state: borrowing GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let count = try reader.ranges()
    let process = try state.selection.general.process(in: debuggee)
    try withUnsafeTemporaryAllocation(of: Int.self, capacity: count,
                                      { sizes throws(GDBHandlerError) in
      try withUnsafeTemporaryAllocation(of: UInt8.self,
                                        capacity: writer.output.freeCapacity,
                                        { buffer throws(GDBHandlerError) in
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        var reader = GDBPacketReader(payload.extracting(0...))
        for index in 0 ..< count {
          let (address, requested) = try reader.range()
          guard requested <= UInt64(output.freeCapacity) else {
            throw .capacity
          }
          let start = output.count
          do throws(Debuggee.Error) {
            try read(process, address: address, size: Int(requested),
                     into: &output)
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
          capacity += UInt64(sizes[index]).digits
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

extension DebugSession {
  internal borrowing func search(_ payload: borrowing Span<UInt8>,
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
    let process = try state.selection.general.process(in: debuggee)
    let result =
        try translate(search(process, address: address, length: length,
                             pattern: pattern))
    guard let result else {
      return try writer.append("0")
    }
    try writer.append("1,")
    try writer.hex(result.rawValue)
  }

  internal mutating func write(memory payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested =
        try reader.length(delimiter: UInt8(ascii: ":"), maximum: Int.max / 2)
    guard reader.count == requested * 2 else {
      throw .malformed
    }
    try writer.output.decode(reader.remaining())
    let process = try state.selection.general.process(in: debuggee)
    let count = try translate(write(process, address: address,
                                    bytes: writer.output.span))
    writer.output.removeAll()
    guard count == requested else {
      throw .debuggee(.memory)
    }
    try writer.append("OK")
  }
}

extension DebugSession {
  internal borrowing func read(binary payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let count = try reader.length()
    guard count <= writer.output.freeCapacity else {
      throw .capacity
    }
    let process = try state.selection.general.process(in: debuggee)
    let start = writer.output.count
    try translate(read(process, address: address, size: count,
                       into: &writer.output))
    guard writer.output.count - start <= count else {
      throw .debuggee(.memory)
    }
  }
}

extension DebugSession {
  internal mutating func write(binary payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try reader.address()
    let requested = try reader.length(delimiter: UInt8(ascii: ":"))
    let bytes = reader.remaining()
    guard bytes.count == requested else {
      throw .malformed
    }
    let process = try state.selection.general.process(in: debuggee)
    let count = try translate(write(process, address: address, bytes: bytes))
    guard count == requested else {
      throw .debuggee(.memory)
    }
    try writer.append("OK")
  }
}

extension Debuggee {
  internal borrowing func region(_ payload: borrowing Span<UInt8>,
                                 state: borrowing GDBRemoteSessionState,
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
    let process = try state.selection.general.process(in: self)
    let region = try translate(NativeMemory.region(process, address: address))
    try writer.emit(region)
  }
}

extension GDBPacketWriter {
  fileprivate mutating func emit(_ region: borrowing Debuggee.MemoryRegion)
      throws(GDBHandlerError) {
    try append("start:")
    try hex(region.address.rawValue)
    try append(";size:")
    try hex(region.size)
    try append(UInt8(ascii: ";"))
    if region.readable || region.writable || region.executable {
      try append("permissions:")
      if region.readable {
        try append(UInt8(ascii: "r"))
      }
      if region.writable {
        try append(UInt8(ascii: "w"))
      }
      if region.executable {
        try append(UInt8(ascii: "x"))
      }
      try append(UInt8(ascii: ";"))
    }
    if let name = region.name {
      try append("name:")
      try encoded(name)
      try append(UInt8(ascii: ";"))
    }
    if let kind = region.kind {
      try append("type:")
      switch kind {
      case .heap(let allocation):
        try append("heap")
        switch allocation {
        case .large: try append(",malloc-large")
        case .small: try append(",malloc-small")
        case .tiny: try append(",malloc-tiny")
        case .unknown: break
        }
      case .malloc(let allocation):
        switch allocation {
        case .guarded: try append("malloc-guard")
        case .metadata: try append("malloc-metadata")
        case .reserved: try append("malloc-reserved")
        }
      case .stack(let guarded):
        try append(guarded ? "stack-guard" : "stack")
      }
      try append(UInt8(ascii: ";"))
    }
  }
}

extension GDBPacketReader {
  fileprivate mutating func ranges() throws(GDBHandlerError) -> Int {
    var count = 0
    while empty == false {
      _ = try range()
      count += 1
    }
    guard count > 0 else {
      throw .malformed
    }
    return count
  }

  fileprivate mutating func range() throws(GDBHandlerError)
      -> (Debuggee.Address, UInt64) {
    let address = try address()
    let length = try hex()
    let comma = consume(UInt8(ascii: ","))
    if consume(UInt8(ascii: ";")) {
      guard empty else {
        throw .malformed
      }
    } else {
      guard comma, empty == false else {
        throw .malformed
      }
    }
    return (address, length)
  }

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
