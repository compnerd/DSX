// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private typealias Response =
    (inout GDBPacketWriter) throws(GDBHandlerError) -> Void

@Suite
internal struct GDBImagePacketTests {
  @Test
  internal func request() throws {
    let json =
        "{\"fetch_all_solibs\":true,\"information-level\":" +
        "\"address-only\",\"report_load_commands\":false}"
    let payload = Array(json.utf8)
    let request = try GDBLibrariesPacket.Request(payload.span)
    #expect(request.all)
    #expect(request.addresses == nil)
    #expect(request.style == .address)

    let source =
        "{\"information-level\":\"full\"," +
        "\"solib_addresses\":[1,42]}"
    let selected = Array(source.utf8)
    let selection = try GDBLibrariesPacket.Request(selected.span)
    #expect(selection.all == false)
    #expect(selection.addresses == [1, 42])
    #expect(selection.style == .full)

    let empty = Array("{}".utf8)
    let probe = try GDBLibrariesPacket.Request(empty.span)
    #expect(probe.all == false)
    #expect(probe.addresses == nil)

    for (level, style) in [
      ("address-only", Debuggee.Image.Style.address),
      ("address-name", .name),
      ("address-name-uuid", .identifier),
      ("full", .full),
    ] {
      let payload = Array("{\"information-level\":\"\(level)\"}".utf8)
      #expect(try GDBLibrariesPacket.Request(payload.span).style == style)
    }
  }

  @Test
  internal func malformed() {
    let json =
        "{\"fetch_all_solibs\":true," +
        "\"fetch_all_solibs\":true}"
    let duplicate = Array(json.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try GDBLibrariesPacket.Request(duplicate.span)
    }

    let unknown = Array("{\"fetch_all_solibs\":null}".utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try GDBLibrariesPacket.Request(unknown.span)
    }
  }

  @Test
  internal func offsets() throws {
    let segment =
        Debuggee.ImageOffsets.segments(text: Debuggee.Address(rawValue: 0x1234),
                                       data: nil)
    let segments = try response { writer throws(GDBHandlerError) in
      try GDBOffsetsPacket.write(segment, writer: &writer)
    }
    #expect(segments == Array("TextSeg=1234".utf8))

    let sections = try response { writer throws(GDBHandlerError) in
      try GDBOffsetsPacket.write(.sections(text: 0x1234, data: 0x5678),
                                 writer: &writer)
    }
    #expect(sections == Array("Text=1234;Data=5678;Bss=5678".utf8))
  }

  @Test
  internal func image() throws {
    let header =
        Debuggee.ImageHeader(magic: 0xfeed_facf, cpu: 0x0100_000c, subtype: 2,
                             file: 6, flags: 0x85, size: 4096)
    let segment =
        Debuggee.ImageSegment(name: "__TEXT", address: 0x1000, size: 0x2000,
                              offset: 0, bytes: 0x1800, protection: 5)
    let image =
        Debuggee.ImageDescription(header: header, segments: [segment],
                                  identifier: "0123")
    let output = try response { writer throws(GDBHandlerError) in
      try GDBLibrariesPacket.write(image, writer: &writer)
    }
    let expected =
        ",\"mach_header\":{\"magic\":4277009103,\"cputype\":16777228," +
        "\"cpusubtype\":2,\"filetype\":6,\"flags\":133," +
        "\"sizeof_mh_and_loadcmds\":4096},\"segments\":[{" +
        "\"name\":\"__TEXT\",\"vmaddr\":4096,\"vmsize\":8192," +
        "\"fileoff\":0,\"filesize\":6144,\"maxprot\":5}]," +
        "\"uuid\":\"0123\""
    #expect(output == Array(expected.utf8))

    let identifier = try response { writer throws(GDBHandlerError) in
      try GDBLibrariesPacket.write(image, style: .identifier, writer: &writer)
    }
    #expect(identifier == Array(",\"uuid\":\"0123\"".utf8))
  }

  @Test
  internal func loader() throws {
    let output = try response { writer throws(GDBHandlerError) in
      try GDBLoaderPacket.write(Debuggee.Loader(value: 0x10), writer: &writer)
    }
    let expected =
        "{\"process_state_value\":16,\"process_state string\":" +
        "\"dyld_process_state_dyld_initialized\"}"
    #expect(output == Array(expected.utf8))

    let unknown = try response { writer throws(GDBHandlerError) in
      try GDBLoaderPacket.write(Debuggee.Loader(value: 0xff), writer: &writer)
    }
    #expect(unknown == Array("{\"process_state_value\":255}".utf8))
  }
}

private func response(_ body: Response) throws -> Array<UInt8> {
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(consume output)
    do throws(GDBHandlerError) {
      try body(&writer)
    } catch {
      output = writer.finish()
      throw error
    }
    output = writer.finish()
  }
  return response
}
