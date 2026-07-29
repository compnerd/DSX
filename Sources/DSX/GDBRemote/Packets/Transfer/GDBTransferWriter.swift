// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func transfer(_ process: ProcessIdentifier, offset: UInt64,
                                  length: UInt64, svr4: Bool,
                                  executable: String?) throws(GDBHandlerError) {
    try transfer(offset: offset,
                 length: length) { emitter throws(Debuggee.Error) in
      var images = try NativeImageCursor(process, svr4: svr4)
      if svr4 {
        emitter.append("<?xml version=\"1.0\"?>")
        emitter.append("<library-list-svr4 version=\"1.0\">")
      } else {
        emitter.append("<?xml version=\"1.0\"?><library-list>")
      }
      while emitter.more == false, let image = try images.next() {
        emitter.image(image, svr4: svr4, executable: executable)
      }
      if emitter.more == false {
        emitter.append(svr4 ? "</library-list-svr4>" : "</library-list>")
      }
    }
  }

  internal mutating func transfer(offset: UInt64, length: UInt64,
                                  _ body: GDBTransferEmitterBody)
      throws(GDBHandlerError) {
    let marker = output.count
    let limit = try begin(length)
    var emitter =
        GDBTransferEmitter(consume output, offset: offset, limit: limit)
    var failure: Debuggee.Error?
    do throws(Debuggee.Error) {
      try body(&emitter)
    } catch {
      failure = error
    }
    let more = emitter.more
    self = GDBPacketWriter(emitter.finish())
    if let failure {
      throw .debuggee(failure)
    }
    output[marker] = more ? UInt8(ascii: "m") : UInt8(ascii: "l")
  }

  internal mutating func transfer(_ process: ProcessIdentifier, offset: UInt64,
                                  length: UInt64) throws(GDBHandlerError) {
    try transfer(offset: offset,
                 length: length) { emitter throws(Debuggee.Error) in
      emitter.append("<?xml version=\"1.0\"?>")
      emitter.append("<!DOCTYPE memory-map SYSTEM \"memory-map.dtd\">")
      emitter.append("<memory-map>")
      var address: UInt64 = 0
      while emitter.more == false {
        let region: Debuggee.MemoryRegion
        do throws(Debuggee.Error) {
          let location = Debuggee.Address(rawValue: address)
          region = try NativeMemory.region(process, address: location)
        } catch .memory {
          break
        }
        guard region.address.rawValue >= address else {
          break
        }
        if region.readable || region.writable || region.executable {
          let kind: StaticString = region.writable ? "ram" : "rom"
          emitter.append("<memory type=\"")
          emitter.append(kind)
          emitter.append("\" start=\"0x")
          emitter.hex(region.address.rawValue)
          emitter.append("\" length=\"0x")
          emitter.hex(region.size)
          emitter.append("\"/>")
        }
        let (next, overflow) =
            region.address.rawValue.addingReportingOverflow(region.size)
        if overflow || region.size == 0 || next <= address {
          break
        }
        address = next
      }
      if emitter.more {
        return
      }
      emitter.append("</memory-map>")
    }
  }

  internal mutating func transfer(length: UInt64, body: GDBTransferBody)
      throws(GDBHandlerError) {
    let marker = output.count
    let limit = try begin(length)
    let start = output.count
    let status = try translate(body(limit, &output))
    guard output.count - start <= limit else {
      throw .capacity
    }
    output[marker] = switch status {
    case .last: UInt8(ascii: "l")
    case .more: UInt8(ascii: "m")
    }
  }

  private mutating func begin(_ length: UInt64) throws(GDBHandlerError) -> Int {
    guard output.freeCapacity > 0 else {
      throw .capacity
    }
    let requested = min(length, UInt64(Int.max))
    let limit = min(Int(requested), output.freeCapacity - 1)
    try append(0x00)
    return limit
  }
}

extension GDBTransferEmitter {
  fileprivate mutating func image(_ image: borrowing Debuggee.Image, svr4: Bool,
                                  executable: String?) {
    if svr4 {
      if image.main {
        return
      }
      guard let link = image.link, let dynamic = image.dynamic else {
        return
      }
      append("<library name=\"")
      xml(image.path, slash: true)
      append("\" lm=\"0x")
      hex(link.rawValue)
      append("\" l_addr=\"0x")
      hex(image.base.rawValue)
      append("\" l_ld=\"0x")
      hex(dynamic.rawValue)
      return append("\"/>")
    }
    let path = image.main ? executable ?? image.path : image.path
    append("<library name=\"")
    xml(path, slash: true)
    append("\">")
    if image.sections.isEmpty {
      append("<section address=\"0x")
      hex(image.base.rawValue)
      append("\"/>")
    } else {
      for section in image.sections {
        append("<section address=\"0x")
        hex(section.rawValue)
        append("\"/>")
      }
    }
    append("</library>")
  }
}

internal typealias GDBTransferBody =
    (Int, inout OutputSpan<UInt8>) throws(Debuggee.Error) -> ReadStatus
internal typealias GDBTransferEmitterBody =
    (inout GDBTransferEmitter) throws(Debuggee.Error) -> Void
