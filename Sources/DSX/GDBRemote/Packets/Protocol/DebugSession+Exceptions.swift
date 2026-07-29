// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func ignore(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.active)
    }
    guard !payload.isEmpty else {
      throw .code(GDBErrorCode.exception)
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    var ignored = Debuggee.ExceptionMask()
    while true {
      let exception: Debuggee.ExceptionMask = switch () {
      case _ where reader.consume("EXC_BAD_ACCESS"): .access
      case _ where reader.consume("EXC_BAD_INSTRUCTION"): .instruction
      case _ where reader.consume("EXC_ARITHMETIC"): .arithmetic
      case _ where reader.consume("EXC_RESOURCE"): .resource
      case _ where reader.consume("EXC_GUARD"): .guarded
      case _ where reader.consume("EXC_SYSCALL"): .syscall
      default: throw .code(GDBErrorCode.exception)
      }
      ignored.formUnion(exception)
      if reader.empty {
        break
      }
      guard reader.consume(UInt8(ascii: "|")) else {
        throw .code(GDBErrorCode.exception)
      }
    }
    try translate(ignore(ignored))
    try writer.append("OK")
  }
}
