// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func transfer(_ process: ProcessIdentifier, offset: UInt64,
                                  length: UInt64, svr4: Bool,
                                  executable: String?) throws(GDBHandlerError) {
    try transfer(length: length) { limit, output throws(Debuggee.Error) in
      var images = try NativeImageCursor(process, svr4: svr4)
      var emitter = GDBTransferEmitter(offset: offset, limit: limit)
      if svr4 {
        emitter.append("<?xml version=\"1.0\"?>", into: &output)
        emitter.append("<library-list-svr4 version=\"1.0\">", into: &output)
      } else {
        emitter.append("<?xml version=\"1.0\"?><library-list>", into: &output)
      }
      while emitter.more == false, let image = try images.next() {
        emitter.image(image, svr4: svr4, executable: executable, into: &output)
      }
      if emitter.more == false {
        emitter.append(svr4 ? "</library-list-svr4>" : "</library-list>",
                       into: &output)
      }
      return emitter.more ? .more : .last
    }
  }

  internal mutating func transfer(offset: UInt64, length: UInt64,
                                  _ body: GDBTransferEmitterBody)
      throws(GDBHandlerError) {
    try transfer(length: length) { limit, output in
      var emitter = GDBTransferEmitter(offset: offset, limit: limit)
      body(&emitter, &output)
      return emitter.more ? .more : .last
    }
  }

  internal mutating func transfer(_ process: ProcessIdentifier, offset: UInt64,
                                  length: UInt64) throws(GDBHandlerError) {
    try transfer(length: length) { limit, output throws(Debuggee.Error) in
      var emitter = GDBTransferEmitter(offset: offset, limit: limit)
      emitter.append("<?xml version=\"1.0\"?>", into: &output)
      emitter.append("<!DOCTYPE memory-map SYSTEM \"memory-map.dtd\">",
                     into: &output)
      emitter.append("<memory-map>", into: &output)
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
          emitter.append("<memory type=\"", into: &output)
          emitter.append(kind, into: &output)
          emitter.append("\" start=\"0x", into: &output)
          emitter.hex(region.address.rawValue, into: &output)
          emitter.append("\" length=\"0x", into: &output)
          emitter.hex(region.size, into: &output)
          emitter.append("\"/>", into: &output)
        }
        let (next, overflow) =
            region.address.rawValue.addingReportingOverflow(region.size)
        if overflow || region.size == 0 || next <= address {
          break
        }
        address = next
      }
      if emitter.more {
        return .more
      }
      emitter.append("</memory-map>", into: &output)
      return emitter.more ? .more : .last
    }
  }

  internal mutating func transfer(length: UInt64, body: GDBTransferBody)
      throws(GDBHandlerError) {
    guard output.freeCapacity > 0 else {
      throw .capacity
    }
    let requested = min(length, UInt64(Int.max))
    let limit = min(Int(requested), output.freeCapacity - 1)
    let marker = output.count
    try append(0x00)
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
}

extension GDBTransferEmitter {
  fileprivate mutating func image(_ image: borrowing Debuggee.Image, svr4: Bool,
                                  executable: String?,
                                  into output: inout OutputSpan<UInt8>) {
    if svr4 {
      if image.main {
        return
      }
      guard let link = image.link, let dynamic = image.dynamic else {
        return
      }
      append("<library name=\"", into: &output)
      xml(image.path, slash: true, into: &output)
      append("\" lm=\"0x", into: &output)
      hex(link.rawValue, into: &output)
      append("\" l_addr=\"0x", into: &output)
      hex(image.base.rawValue, into: &output)
      append("\" l_ld=\"0x", into: &output)
      hex(dynamic.rawValue, into: &output)
      return append("\"/>", into: &output)
    }
    let path = image.main ? executable ?? image.path : image.path
    append("<library name=\"", into: &output)
    xml(path, slash: true, into: &output)
    append("\">", into: &output)
    if image.sections.isEmpty {
      append("<section address=\"0x", into: &output)
      hex(image.base.rawValue, into: &output)
      append("\"/>", into: &output)
    } else {
      for section in image.sections {
        append("<section address=\"0x", into: &output)
        hex(section.rawValue, into: &output)
        append("\"/>", into: &output)
      }
    }
    append("</library>", into: &output)
  }
}

internal typealias GDBTransferBody =
    (Int, inout OutputSpan<UInt8>) throws(Debuggee.Error) -> ReadStatus
internal typealias GDBTransferEmitterBody =
    (inout GDBTransferEmitter, inout OutputSpan<UInt8>) -> Void
