// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRegisterPacket {
  internal static func info(_ payload: borrowing Span<UInt8>,
                            registers: RegisterDescription,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let number = try reader.hex()
    guard reader.empty, let number = Int(exactly: number),
        let register =
            registers.register(number,
                               compatibility: state.compatibility) else {
      throw .code(GDBErrorCode.register)
    }
    try writer.append("name:")
    try writer.append(registers.name(register))
    try writer.append(UInt8(ascii: ";"))
    if let alias = registers.alias(register) {
      try writer.append("alt-name:")
      try writer.append(alias)
      try writer.append(UInt8(ascii: ";"))
    }
    try writer.append("bitsize:")
    try writer.decimal(register.bits)
    try writer.append(";offset:")
    try writer.decimal(register.offset)
    try writer.append(";encoding:")
    try writer.append(register.encoding.name)
    try writer.append(";format:")
    try writer.append(register.format.name)
    try writer.append(UInt8(ascii: ";"))
    if let set = registers.set(Int(register.set.rawValue)) {
      try writer.append("set:")
      try writer.append(set.name)
      try writer.append(UInt8(ascii: ";"))
    }
    if let dwarf = register.numbers.dwarf {
      try writer.append("gcc:")
      try writer.decimal(dwarf)
      try writer.append(";dwarf:")
      try writer.decimal(dwarf)
      try writer.append(UInt8(ascii: ";"))
    }
    if let ehframe = register.numbers.ehframe {
      try writer.append("ehframe:")
      try writer.decimal(ehframe)
      try writer.append(UInt8(ascii: ";"))
    }
    if let name = ABI.role(register)?.name {
      try writer.append("generic:")
      try writer.append(name)
      try writer.append(UInt8(ascii: ";"))
    }
    try relations(register.relations.containers, name: "container-regs:",
                  registers: registers, compatibility: state.compatibility,
                  writer: &writer)
    try relations(register.relations.invalidates, name: "invalidate-regs:",
                  registers: registers, compatibility: state.compatibility,
                  writer: &writer)
  }
}

private func relations(_ range: Range<Int>, name: StaticString,
                       registers: RegisterDescription,
                       compatibility: CompatibilityMode,
                       writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  guard !range.isEmpty else {
    return
  }
  try writer.append(name)
  var separator = false
  for index in range {
    guard let identifier = registers.relation(index),
        let register = registers.register(identifier),
        let number = registers.number(register,
                                      compatibility: compatibility) else {
      continue
    }
    if separator {
      try writer.append(UInt8(ascii: ","))
    }
    try writer.hex(UInt64(number))
    separator = true
  }
  try writer.append(UInt8(ascii: ";"))
}

extension GDBPacketWriter {
  fileprivate mutating func decimal(_ value: Int) throws(GDBHandlerError) {
    guard value >= 0 else {
      throw .malformed
    }
    try decimal(UInt64(value))
  }
}
