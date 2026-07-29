// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private typealias FileError = Debuggee.Error

internal enum GDBFilePacket {
  private static let kCapacity = Configuration.FileTransferCapacity

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              files: inout FileSystem, working: String? = nil,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let operation = try reader.field(UInt8(ascii: ":"))
    switch true {
    case reader.matches(operation, value: "open"):
      try open(&reader, files: &files, working: working, writer: &writer)
    case reader.matches(operation, value: "close"):
      try close(&reader, files: &files, writer: &writer)
    case reader.matches(operation, value: "fstat"):
      try status(&reader, files: &files, writer: &writer)
    case reader.matches(operation, value: "stat"):
      try status(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "lstat"):
      try status(&reader, files: files, working: working, link: true,
                 writer: &writer)
    case reader.matches(operation, value: "MD5"),
         reader.matches(operation, value: "md5"):
      try checksum(&reader, files: &files, working: working, writer: &writer)
    case reader.matches(operation, value: "mode"):
      try mode(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "exists"):
      try exists(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "pread"):
      try read(&reader, files: &files, writer: &writer)
    case reader.matches(operation, value: "pwrite"):
      try write(&reader, files: &files, writer: &writer)
    case reader.matches(operation, value: "size"):
      try size(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "unlink"):
      try remove(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "readlink"):
      try destination(&reader, files: files, working: working, writer: &writer)
    case reader.matches(operation, value: "setfs"):
      try select(&reader, files: &files, writer: &writer)
    case reader.matches(operation, value: "symlink"):
      try link(&reader, files: files, working: working, writer: &writer)
    default:
      throw .unsupported
    }
  }

  private static func open(_ reader: inout GDBPacketReader,
                           files: inout FileSystem, working: String?,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try reader.field(UInt8(ascii: ","))
    let name = try GDBPacketReader.string(reader.span(path))
    let flags = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let mode = try reader.hex()
    guard reader.empty, flags <= UInt64(UInt32.max),
        mode <= UInt64(UInt32.max) else {
      throw .malformed
    }
    let options = options(UInt32(flags))
    let file: FileIdentifier
    do throws(Debuggee.Error) {
      file = try files.open(name, working: working, options: options,
                            mode: UInt32(mode))
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(file.rawValue)
  }

  private static func close(_ reader: inout GDBPacketReader,
                            files: inout FileSystem,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    do throws(Debuggee.Error) {
      try files.close(file)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(0)
  }

  private static func read(_ reader: inout GDBPacketReader,
                           files: inout FileSystem,
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
      try files.read(file, offset: offset, size: limit, into: &writer.output)
    } catch {
      return try failure(error, writer: &writer)
    }
    try prefix(start, writer: &writer)
  }

  private static func status(_ reader: inout GDBPacketReader,
                             files: inout FileSystem,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let file = try FileIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try files.status(file)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.append("F40;")
    try writer.status(status)
  }

  private static func status(_ reader: inout GDBPacketReader,
                             files: borrowing FileSystem, working: String?,
                             link: Bool = false, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try files.status(path, working: working, link: link)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.append("F40;")
    try writer.status(status)
  }

  private static func destination(_ reader: inout GDBPacketReader,
                                  files: borrowing FileSystem, working: String?,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    let destination: String
    do throws(Debuggee.Error) {
      destination = try files.destination(path, working: working)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(UInt64(destination.utf8.count))
    try writer.append(UInt8(ascii: ";"))
    for byte in destination.utf8 {
      try writer.append(byte)
    }
  }

  private static func checksum(_ reader: inout GDBPacketReader,
                               files: inout FileSystem, working: String?,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    let file: FileIdentifier
    do throws(Debuggee.Error) {
      file = try files.open(path, working: working, options: [.read], mode: 0)
    } catch {
      return try unavailable(writer: &writer)
    }
    defer {
      do throws(Debuggee.Error) {
        try files.close(file)
      } catch {
        DSX.log("failed to close checksum input: \(error)", level: .warning,
                channel: .system)
      }
    }
    var checksum = MD5Checksum()
    var offset: UInt64 = 0
    do throws(Debuggee.Error) {
      while true {
        let count =
            try withUnsafeTemporaryAllocation(of: UInt8.self,
                                              capacity: kCapacity,
                                              { buffer throws(FileError) in
          var output = OutputSpan(buffer: buffer, initializedCount: 0)
          try files.read(file, offset: offset, size: buffer.count,
                         into: &output)
          checksum.update(output.span)
          return output.count
        })
        guard count > 0 else {
          break
        }
        offset &+= UInt64(count)
      }
    } catch {
      return try unavailable(writer: &writer)
    }
    let digest = checksum.finish()
    try writer.append("F,")
    try writer.digest(digest)
  }

  private static func mode(_ reader: inout GDBPacketReader,
                           files: borrowing FileSystem, working: String?,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    let status: FileStatus
    do throws(Debuggee.Error) {
      status = try files.status(path, working: working, link: false)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(status.mode & 0x0fff)
  }

  private static func exists(_ reader: inout GDBPacketReader,
                             files: borrowing FileSystem, working: String?,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    do throws(Debuggee.Error) {
      _ = try files.status(path, working: working, link: false)
    } catch .system(let code) {
      if code == 2 {
        try writer.append("F,0")
      } else {
        try failure(.system(code), writer: &writer)
      }
      return
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.append("F,1")
  }

  private static func write(_ reader: inout GDBPacketReader,
                            files: inout FileSystem,
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
      count = try files.write(file, offset: offset, bytes: bytes)
    } catch {
      return try failure(error, writer: &writer)
    }
    guard count >= 0 else {
      throw .debuggee(.state)
    }
    try writer.file(UInt64(count))
  }

  private static func select(_ reader: inout GDBPacketReader,
                             files: inout FileSystem,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    do throws(Debuggee.Error) {
      try files.select(process)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(0)
  }

  private static func remove(_ reader: inout GDBPacketReader,
                             files: borrowing FileSystem, working: String?,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    do throws(Debuggee.Error) {
      try files.remove(path, working: working)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(0)
  }

  private static func link(_ reader: inout GDBPacketReader,
                           files: borrowing FileSystem, working: String?,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let field = try reader.field(UInt8(ascii: ","))
    let target = try GDBPacketReader.string(reader.span(field))
    let path = try GDBPacketReader.string(reader.remaining())
    do throws(Debuggee.Error) {
      try files.link(target, at: path, working: working)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(0)
  }

  private static func size(_ reader: inout GDBPacketReader,
                           files: borrowing FileSystem, working: String?,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try GDBPacketReader.string(reader.remaining())
    let size: UInt64
    do throws(Debuggee.Error) {
      size = try files.size(path, working: working)
    } catch {
      return try failure(error, writer: &writer)
    }
    try writer.file(size)
  }
}

extension GDBPacketWriter {
  fileprivate mutating func status(_ status: FileStatus)
      throws(GDBHandlerError) {
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
}

private func prefix(_ start: Int, writer: inout GDBPacketWriter)
    throws(GDBHandlerError) {
  let count = writer.count - start
  let header = writer.count
  try writer.file(UInt64(count))
  try writer.append(UInt8(ascii: ";"))
  let length = writer.count - header
  var prefix = InlineArray<18, UInt8> { _ in 0 }
  for index in 0 ..< length {
    prefix[index] = writer.output[header + index]
  }
  var index = count
  while index > 0 {
    index -= 1
    writer.output[start + length + index] = writer.output[start + index]
  }
  for index in 0 ..< length {
    writer.output[start + index] = prefix[index]
  }
}

private func unavailable(writer: inout GDBPacketWriter)
    throws(GDBHandlerError) {
  try writer.append("F,x")
}

private func failure(_ error: Debuggee.Error,
                     writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  let failure: FileFailure = switch error {
  case .access: .access
  case .file(let failure): failure
  case .system(let code): FileFailure(native: code)
  case .unsupported: .unsupported
  default: .unknown
  }
  try writer.append("F-1,")
  try writer.hex(UInt64(failure.code))
}

private func options(_ flags: UInt32) -> FileOptions {
  var options = FileOptions()
  switch flags & 0x0003 {
  case 0:
    options.insert(.read)
  case 1:
    options.insert(.write)
  default:
    options.formUnion([.read, .write])
  }
  if flags & 0x0008 > 0 {
    options.insert(.append)
  }
  if flags & 0x0200 > 0 {
    options.insert(.create)
  }
  if flags & 0x0400 > 0 {
    options.insert(.truncate)
  }
  if flags & 0x0800 > 0 {
    options.insert(.exclusive)
  }
  return options
}
