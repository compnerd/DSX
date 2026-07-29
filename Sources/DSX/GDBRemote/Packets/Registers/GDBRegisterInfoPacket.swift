// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension RegisterDescription {
  internal borrowing func info(_ payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let number = try reader.hex()
    guard reader.empty, let number = Int(exactly: number),
        let register =
            register(number, compatibility: state.compatibility) else {
      throw .code(GDBErrorCode.register)
    }
    try writer.emit(register, description: self,
                    compatibility: state.compatibility)
  }
}

extension GDBPacketWriter {
  fileprivate mutating func emit(_ register: RegisterRecord,
                                 description: RegisterDescription,
                                 compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    try append("name:")
    try append(description.name(register))
    try append(UInt8(ascii: ";"))
    if let alias = description.alias(register) {
      try append("alt-name:")
      try append(alias)
      try append(UInt8(ascii: ";"))
    }
    try append("bitsize:")
    try decimal(register.bits)
    try append(";offset:")
    try decimal(register.offset)
    try append(";encoding:")
    try append(register.encoding.name)
    try append(";format:")
    try append(register.format.name)
    try append(UInt8(ascii: ";"))
    if let set = description.set(Int(register.set.rawValue)) {
      try append("set:")
      try append(set.name)
      try append(UInt8(ascii: ";"))
    }
    if let dwarf = register.numbers.dwarf {
      try append("gcc:")
      try decimal(dwarf)
      try append(";dwarf:")
      try decimal(dwarf)
      try append(UInt8(ascii: ";"))
    }
    if let ehframe = register.numbers.ehframe {
      try append("ehframe:")
      try decimal(ehframe)
      try append(UInt8(ascii: ";"))
    }
    if let name = ABI.role(register)?.name {
      try append("generic:")
      try append(name)
      try append(UInt8(ascii: ";"))
    }
    try relations(register.relations.containers, name: "container-regs:",
                  description: description, compatibility: compatibility)
    try relations(register.relations.invalidates, name: "invalidate-regs:",
                  description: description, compatibility: compatibility)
  }
}

extension GDBPacketWriter {
  private mutating func relations(_ range: Range<Int>, name: StaticString,
                                  description: RegisterDescription,
                                  compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    guard !range.isEmpty else {
      return
    }
    try append(name)
    var separator = false
    for index in range {
      guard let identifier = description.relation(index),
          let register = description.register(identifier),
          let number =
              description.number(register, compatibility: compatibility) else {
        continue
      }
      if separator {
        try append(UInt8(ascii: ","))
      }
      try hex(UInt64(number))
      separator = true
    }
    try append(UInt8(ascii: ";"))
  }
}

extension GDBPacketWriter {
  private mutating func decimal(_ value: Int) throws(GDBHandlerError) {
    guard value >= 0 else {
      throw .malformed
    }
    try decimal(UInt64(value))
  }
}
