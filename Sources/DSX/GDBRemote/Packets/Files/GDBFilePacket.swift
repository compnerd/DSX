// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension FileSystem {
  internal mutating func handle(_ payload: borrowing Span<UInt8>,
                                directory: String? = nil,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let operation = try reader.field(UInt8(ascii: ":"))
    switch true {
    case reader.matches(operation, value: "open"):
      try open(&reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "close"):
      try close(&reader, writer: &writer)
    case reader.matches(operation, value: "fstat"):
      try status(&reader, writer: &writer)
    case reader.matches(operation, value: "stat"):
      try status(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "lstat"):
      try status(reader, directory: directory, link: true, writer: &writer)
    case reader.matches(operation, value: "MD5"),
         reader.matches(operation, value: "md5"):
      try checksum(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "mode"):
      try mode(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "exists"):
      try exists(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "pread"):
      try read(&reader, writer: &writer)
    case reader.matches(operation, value: "pwrite"):
      try write(&reader, writer: &writer)
    case reader.matches(operation, value: "size"):
      try size(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "unlink"):
      try remove(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "readlink"):
      try destination(reader, directory: directory, writer: &writer)
    case reader.matches(operation, value: "setfs"):
      try select(&reader, writer: &writer)
    case reader.matches(operation, value: "symlink"):
      try link(&reader, directory: directory, writer: &writer)
    default:
      throw .unsupported
    }
  }

  private mutating func open(_ reader: inout GDBPacketReader,
                             directory: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try reader.field(UInt8(ascii: ","))
    let name = try String(hex: reader.span(path))
    let flags = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let mode = try reader.hex()
    guard reader.empty, flags <= UInt64(UInt32.max),
        mode <= UInt64(UInt32.max) else {
      throw .malformed
    }
    let options = FileOptions(flags: UInt32(flags))
    let file: FileIdentifier
    do throws(Debuggee.Error) {
      file = try open(name, directory: directory, options: options,
                      mode: UInt32(mode))
    } catch {
      return try writer.file(error)
    }
    try writer.file(file.rawValue)
  }

  private mutating func close(_ reader: inout GDBPacketReader,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    do throws(Debuggee.Error) {
      try close(file)
    } catch {
      return try writer.file(error)
    }
    try writer.file(0)
  }

  private borrowing func read(_ reader: inout GDBPacketReader,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let count = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let offset = try reader.hex()
    guard reader.empty, count <= UInt64(Int.max),
        writer.output.freeCapacity >= 18 else {
      throw .malformed
    }
    let limit = min(Int(count), writer.output.freeCapacity - 18)
    let start = writer.count
    do throws(Debuggee.Error) {
      try read(file, offset: offset, size: limit, into: &writer.output)
    } catch {
      return try writer.file(error)
    }
    try writer.prefix(start)
  }

  private borrowing func status(_ reader: inout GDBPacketReader,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try self.status(file)
    } catch {
      return try writer.file(error)
    }
    try writer.append("F40;")
    try writer.emit(status)
  }

  private borrowing func status(_ reader: borrowing GDBPacketReader,
                                directory: String?, link: Bool = false,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try self.status(path, directory: directory, link: link)
    } catch {
      return try writer.file(error)
    }
    try writer.append("F40;")
    try writer.emit(status)
  }

  private borrowing func destination(_ reader: borrowing GDBPacketReader,
                                     directory: String?,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    let destination: String
    do throws(Debuggee.Error) {
      destination = try self.destination(path, directory: directory)
    } catch {
      return try writer.file(error)
    }
    let bytes = destination.utf8Span.span
    try writer.file(UInt64(bytes.count))
    try writer.append(UInt8(ascii: ";"))
    try writer.append(bytes)
  }

  private mutating func checksum(_ reader: borrowing GDBPacketReader,
                                 directory: String?,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    let digest: InlineArray<16, UInt8>
    do throws(Debuggee.Error) {
      digest = try checksum(path, directory: directory)
    } catch {
      return try writer.append("F,x")
    }
    try writer.append("F,")
    try writer.digest(digest)
  }

  private borrowing func mode(_ reader: borrowing GDBPacketReader,
                              directory: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try self.status(path, directory: directory, link: false)
    } catch {
      return try writer.file(error)
    }
    try writer.file(status.mode & 0x0fff)
  }

  private borrowing func exists(_ reader: borrowing GDBPacketReader,
                                directory: String?,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    do throws(Debuggee.Error) {
      _ = try status(path, directory: directory, link: false)
    } catch {
      return try writer.append("F,0")
    }
    try writer.append("F,1")
  }

  private borrowing func write(_ reader: inout GDBPacketReader,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let offset = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let bytes = reader.remaining()
    let count: Int
    do throws(Debuggee.Error) {
      count = try write(file, offset: offset, bytes: bytes)
    } catch {
      return try writer.file(error)
    }
    guard count >= 0 else {
      throw .debuggee(.state)
    }
    try writer.file(UInt64(count))
  }

  private mutating func select(_ reader: inout GDBPacketReader,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    do throws(Debuggee.Error) {
      try select(process)
    } catch {
      return try writer.file(error)
    }
    try writer.file(0)
  }

  private borrowing func remove(_ reader: borrowing GDBPacketReader,
                                directory: String?,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    do throws(Debuggee.Error) {
      try remove(path, directory: directory)
    } catch {
      return try writer.file(error)
    }
    try writer.file(0)
  }

  private borrowing func link(_ reader: inout GDBPacketReader,
                              directory: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let field = try reader.field(UInt8(ascii: ","))
    let target = try String(hex: reader.span(field))
    let path = try String(hex: reader.remaining())
    do throws(Debuggee.Error) {
      try link(target, at: path, directory: directory)
    } catch {
      return try writer.file(error)
    }
    try writer.file(0)
  }

  private borrowing func size(_ reader: borrowing GDBPacketReader,
                              directory: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: reader.remaining())
    let size: UInt64
    do throws(Debuggee.Error) {
      size = try self.size(path, directory: directory)
    } catch {
      return try writer.file(error)
    }
    try writer.file(size)
  }
}

extension GDBPacketWriter {
  fileprivate mutating func emit(_ status: FileStatus) throws(GDBHandlerError) {
    try fixed(status.device, bytes: 4, overflow: 0)
    try fixed(status.inode, bytes: 4, overflow: 0)
    try fixed(status.mode, bytes: 4, overflow: 0)
    try fixed(status.links, bytes: 4, overflow: UInt64(UInt32.max))
    try fixed(status.user, bytes: 4, overflow: 0)
    try fixed(status.group, bytes: 4, overflow: 0)
    try fixed(status.special, bytes: 4, overflow: 0)
    try fixed(status.size, bytes: 8, overflow: 0)
    try fixed(status.block, bytes: 8, overflow: 0)
    try fixed(status.blocks, bytes: 8, overflow: 0)
    try fixed(status.access, bytes: 4, overflow: 0)
    try fixed(status.modification, bytes: 4, overflow: 0)
    try fixed(status.change, bytes: 4, overflow: 0)
  }

  private mutating func fixed(_ value: UInt64, bytes: Int, overflow: UInt64)
      throws(GDBHandlerError) {
    let maximum = bytes == 8 ? UInt64.max : UInt64(UInt32.max)
    let value = value <= maximum ? value : overflow
    for index in 0 ..< bytes {
      let shift = UInt64(bytes - index - 1) * 8
      try append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }

  fileprivate mutating func file(_ value: UInt64) throws(GDBHandlerError) {
    try append(UInt8(ascii: "F"))
    try hex(value)
  }

  fileprivate mutating func digest(_ digest: borrowing InlineArray<16, UInt8>)
      throws(GDBHandlerError) {
    for half in 0 ..< 2 {
      for index in 0 ..< 8 {
        let offset = half * 8 + 7 - index
        try hex(digest[offset])
      }
    }
  }

  fileprivate mutating func prefix(_ start: Int) throws(GDBHandlerError) {
    let size = count - start
    let header = count
    try file(UInt64(size))
    try append(UInt8(ascii: ";"))
    let length = count - header
    var prefix = InlineArray<18, UInt8> { _ in 0 }
    for index in 0 ..< length {
      prefix[index] = output[header + index]
    }
    var index = size
    while index > 0 {
      index -= 1
      output[start + length + index] = output[start + index]
    }
    for index in 0 ..< length {
      output[start + index] = prefix[index]
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func file(_ error: Debuggee.Error)
      throws(GDBHandlerError) {
    let failure: FileFailure = switch error {
    case .access: .access
    case .file(let failure): failure
    case .system(let code): FileFailure(native: code)
    case .unsupported: .unsupported
    default: .unknown
    }
    try append("F-1,")
    try hex(UInt64(failure.code))
  }
}

extension FileOptions {
  fileprivate init(flags: UInt32) {
    self.init()
    switch flags & 0x0003 {
    case 0:
      insert(.read)
    case 1:
      insert(.write)
    default:
      formUnion([.read, .write])
    }
    if flags & 0x0008 > 0 {
      insert(.append)
    }
    if flags & 0x0200 > 0 {
      insert(.create)
    }
    if flags & 0x0400 > 0 {
      insert(.truncate)
    }
    if flags & 0x0800 > 0 {
      insert(.exclusive)
    }
  }
}
