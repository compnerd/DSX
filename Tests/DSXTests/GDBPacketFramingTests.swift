// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable internal import DSX

extension GDBPacketEncoding {
  internal func frame(_ message: borrowing Span<UInt8>,
                      output: inout OutputSpan<UInt8>) {
    output.append(UInt8(ascii: "$"))
    var checksum: UInt8 = 0
    for index in 0 ..< message.count {
      let byte = message[index]
      let escaped = byte == UInt8(ascii: "#") || byte == UInt8(ascii: "$") ||
          byte == UInt8(ascii: "}") || byte == UInt8(ascii: "*")
      if self == .binary, escaped {
        output.append(UInt8(ascii: "}"))
        output.append(byte ^ 0x20)
        checksum &+= UInt8(ascii: "}")
        checksum &+= byte ^ 0x20
      } else {
        output.append(byte)
        checksum &+= byte
      }
    }
    output.append(UInt8(ascii: "#"))
    output.append((checksum >> 4).hexadecimal)
    output.append(checksum.hexadecimal)
  }
}
