// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import Testing
@testable import DSX

@Suite
internal struct GDBThreadContextTests {
  @Test
  internal func probe() throws(GDBHandlerError) {
    let bytes = Array(":".utf8)
    #expect(try Debuggee.Thread.Layout(bytes.span) == nil)
  }

  @Test
  internal func minimal() throws(GDBHandlerError) {
    let bytes = Array(#":{"thread":7}"#.utf8)
    let layout = try Debuggee.Thread.Layout(bytes.span)
    #expect(layout?.thread.rawValue == 7)
    #expect(layout?.address == nil)
    #expect(layout?.base == nil)
    #expect(layout?.size == nil)
    #expect(layout?.quality == nil)
  }

  @Test
  internal func partial() throws(GDBHandlerError) {
    let value = #":{"thread":7,"plo_pthread_tsd_base_offset":224}"#
    let bytes = Array(value.utf8)
    let layout = try Debuggee.Thread.Layout(bytes.span)
    #expect(layout?.thread.rawValue == 7)
    #expect(layout?.base == 224)
    #expect(layout?.address == nil)
    #expect(layout?.size == nil)
  }

  @Test(arguments: [": { \"thread\" : 7 } \r\n", ":\n{\t\"thread\"\r:\n7\t}\r"])
  internal func whitespace(_ value: String) throws(GDBHandlerError) {
    let bytes = Array(value.utf8)
    let layout = try Debuggee.Thread.Layout(bytes.span)
    #expect(layout?.thread.rawValue == 7)
    #expect(layout?.size == nil)
  }

  @Test
  internal func hints() throws(GDBHandlerError) {
    let value = """
        :{"thread":7,"plo_pthread_tsd_base_address_offset":0,\
        "plo_pthread_tsd_base_offset":224,\
        "plo_pthread_tsd_entry_size":8,"dti_qos_class_index":3}
        """
    let bytes = Array(value.utf8)
    let layout = try Debuggee.Thread.Layout(bytes.span)
    #expect(layout?.thread.rawValue == 7)
    #expect(layout?.address == 0)
    #expect(layout?.base == 224)
    #expect(layout?.size == 8)
    #expect(layout?.quality == 3)
  }

  @Test(arguments: [":{}", #":{"thread":-1}"#, #":{"thread":1}x"#,
                    #":{"thread":18446744073709551616}"#])
  internal func malformed(_ value: String) {
    let bytes = Array(value.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try Debuggee.Thread.Layout(bytes.span)
    }
  }

  @Test
  internal func encoding() throws(GDBHandlerError) {
    let context = Debuggee.Thread.Context(pthread: 100, storage: nil,
                                          queue: 900, quality: nil)
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: 128) { output throws(GDBHandlerError) in
      var writer = GDBPacketWriter(consume output)
      do throws(GDBHandlerError) {
        try writer.emit(context)
      } catch {
        output = writer.finish()
        throw error
      }
      output = writer.finish()
    }
    let value = String(decoding: bytes, as: UTF8.self)
    #expect(value == #"{"pthread_t":100,"dispatch_queue_t":900}"#)
  }
}
