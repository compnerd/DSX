// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
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
}
