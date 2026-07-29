// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxARM64RegisterTests {
  @Test(arguments: [0, 16, 32, 64, 128, 256], [false, true])
  internal func layout(_ length: Int, _ authentication: Bool) throws {
    let configuration =
        RegisterConfiguration(vector: length, authentication: authentication)
    let description = RegisterDescription(configuration)
    let expected = 162 + (authentication ? 2 : 0) + (length > 0 ? 50 : 0)
    #expect(description.count == expected)
    for number in 0 ..< expected {
      let record =
          try #require(description.register(number, compatibility: .lldb))
      #expect(record.numbers.lldb == number)
    }
    #expect(description.register(expected, compatibility: .lldb) == nil)
    let mask = description.register(RegisterIdentifier(rawValue: 166))
    #expect((mask != nil) == authentication)
    guard length > 0 else {
      #expect(description.register(RegisterIdentifier(rawValue: 167)) == nil)
      return
    }
    let vg =
        try #require(description.register(RegisterIdentifier(rawValue: 167)))
    #expect(vg.expedited)
    #expect(vg.bytes == 8)
    let z =
        try #require(description.register(RegisterIdentifier(rawValue: 168)))
    #expect(z.bytes == length)
    #expect(z.offset == vg.offset + 8)
    let ffr =
        try #require(description.register(RegisterIdentifier(rawValue: 216)))
    #expect(ffr.bytes == length / 8)
    #expect(ffr.offset == z.offset + 32 * length + 16 * length / 8)
    #expect(ffr.numbers.dwarf == 47)
  }

  @Test(arguments: [0, 16, 64, 256])
  internal func features(_ length: Int) throws {
    let configuration =
        RegisterConfiguration(vector: length, authentication: true)
    let description = RegisterDescription(configuration)
    let capacity = Configuration.PacketCapacity
    let xml =
        try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                          { buffer throws(GDBHandlerError) in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      try writer.emit(description, offset: 0, length: UInt64(capacity),
                      compatibility: .gdb)
      let output = writer.finish()
      return String(decoding: buffer.prefix(output.count), as: UTF8.self)
    })
    let sve = xml.contains("<feature name=\"org.gnu.gdb.aarch64.sve\">")
    let fpu = xml.contains("<feature name=\"org.gnu.gdb.aarch64.fpu\">")
    #expect(sve == (length > 0))
    #expect(fpu == (length == 0))
    #expect(xml.contains("name=\"fpsr\""))
    #expect(xml.contains("name=\"fpcr\""))
    #expect(xml.contains("<reg name=\"x29\""))
    #expect(xml.contains("<reg name=\"x30\""))
    #expect(xml.contains("<reg name=\"pauth_dmask\""))
    #expect(xml.contains("<reg name=\"pauth_cmask\""))
    #expect(xml.contains("count=\"0\"") == false)
    if length > 0 {
      let vector = "id=\"sve_vector\" type=\"uint8\" count=\"\(length)\""
      #expect(xml.contains(vector))
    }
  }

  @Test(arguments: [0, 1, 15, 17, 257, 512])
  internal func invalid(_ length: UInt16) {
    let header = LinuxSVEHeader(length: length, limit: 512)
    #expect(header.valid == false)
  }

  @Test(arguments: [16, 32, 64, 128, 256])
  internal func payload(_ length: UInt16) {
    var header = LinuxSVEHeader(size: 16, length: length, limit: 256)
    #expect(header.valid)
    #expect(header.format == .inactive)
    #expect(header.minimum == 16)
    header.size = UInt32(LinuxSVEHeader.kFPSIMDSize)
    #expect(header.valid)
    #expect(header.format == .fpsimd)
    #expect(header.minimum == 544)
    header.flags = 1
    header.size = UInt32(header.capacity)
    #expect(header.valid)
    #expect(header.format == .full)
    #expect(header.control % 16 == 0)
    header.size -= 1
    #expect(header.valid == false)
  }
}
#endif
