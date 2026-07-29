// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBRegisterFeaturesPacket {
  internal static func write(offset: UInt64, length: UInt64,
                             registers: RegisterDescription,
                             compatibility: CompatibilityMode,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.transfer(offset: offset, length: length) { emitter, output in
      emitter.write(registers, compatibility: compatibility, into: &output)
    }
  }
}

extension GDBTransferEmitter {
  fileprivate mutating func write(_ description: RegisterDescription,
                                  compatibility: CompatibilityMode,
                                  into output: inout OutputSpan<UInt8>) {
    append("<?xml version=\"1.0\"?><!DOCTYPE target SYSTEM ", into: &output)
    append("\"gdb-target.dtd\"><target><architecture>", into: &output)
    append(RegisterDescription.architecture, into: &output)
    append("</architecture>", into: &output)
    let features = compatibility == .lldb ? 1 : description.features
    for index in 0 ..< features {
      guard let feature = description.feature(index) else {
        continue
      }
      append("<feature name=\"", into: &output)
      append(feature.name, into: &output)
      append("\">", into: &output)
      for identifier in 0 ..< description.types {
        guard let type = description.type(identifier), compatibility == .lldb ||
            type.feature == feature.identifier else {
          continue
        }
        write(type, description: description, into: &output)
      }
      for number in 0 ..< description.count {
        guard let register =
            description.register(number, compatibility: compatibility),
            compatibility == .lldb ||
            register.feature == feature.identifier else {
          continue
        }
        write(register, number: number, description: description,
              compatibility: compatibility, into: &output)
      }
      append("</feature>", into: &output)
    }
    append("</target>", into: &output)
  }

  private mutating func write(_ type: RegisterTypeRecord,
                              description: RegisterDescription,
                              into output: inout OutputSpan<UInt8>) {
    switch type.kind {
    case .enum:
      append("<enum id=\"", into: &output)
      append(type.name, into: &output)
      append("\" size=\"", into: &output)
      decimal((type.bits ?? 0) / 8, into: &output)
      append("\">", into: &output)
      for index in type.fields {
        guard let field = description.field(index) else {
          continue
        }
        append("<evalue name=\"", into: &output)
        append(field.name, into: &output)
        append("\" value=\"", into: &output)
        decimal(field.start, into: &output)
        append("\"/>", into: &output)
      }
      append("</enum>", into: &output)
    case .flags:
      append("<flags id=\"", into: &output)
      append(type.name, into: &output)
      append("\" size=\"", into: &output)
      decimal((type.bits ?? 0) / 8, into: &output)
      append("\">", into: &output)
      for index in type.fields {
        guard let field = description.field(index) else {
          continue
        }
        append("<field name=\"", into: &output)
        append(field.name, into: &output)
        append("\" start=\"", into: &output)
        decimal(field.start, into: &output)
        append("\" end=\"", into: &output)
        decimal(field.end, into: &output)
        if let identifier = field.type,
            let enumeration = description.type(Int(identifier.rawValue)) {
          append("\" type=\"", into: &output)
          append(enumeration.name, into: &output)
        }
        append("\"/>", into: &output)
      }
      append("</flags>", into: &output)
    case .vector:
      append("<vector id=\"", into: &output)
      append(type.name, into: &output)
      if let element = type.element {
        append("\" type=\"", into: &output)
        append(element, into: &output)
      }
      if let count = type.count {
        append("\" count=\"", into: &output)
        decimal(count, into: &output)
      }
      append("\"/>", into: &output)
    }
  }

  private mutating func write(_ register: RegisterRecord, number: Int,
                              description: RegisterDescription,
                              compatibility: CompatibilityMode,
                              into output: inout OutputSpan<UInt8>) {
    append("<reg name=\"", into: &output)
    append(description.name(register), into: &output)
    append("\"", into: &output)
    if let alias = description.alias(register) {
      append(" altname=\"", into: &output)
      append(alias, into: &output)
      append("\"", into: &output)
    }
    append(" bitsize=\"", into: &output)
    decimal(register.bits, into: &output)
    append("\" regnum=\"", into: &output)
    decimal(number, into: &output)
    append("\" offset=\"", into: &output)
    decimal(register.offset, into: &output)
    append("\" encoding=\"", into: &output)
    append(register.encoding.name, into: &output)
    append("\" format=\"", into: &output)
    append(register.format.name, into: &output)
    if let identifier = register.type,
        let type = description.type(Int(identifier.rawValue)) {
      append("\" type=\"", into: &output)
      append(type.name, into: &output)
    }
    if let set = description.set(Int(register.set.rawValue)) {
      append("\" group=\"", into: &output)
      append(set.name, into: &output)
    }
    if let ehframe = register.numbers.ehframe {
      append("\" ehframe_regnum=\"", into: &output)
      decimal(ehframe, into: &output)
    }
    if let dwarf = register.numbers.dwarf {
      append("\" dwarf_regnum=\"", into: &output)
      decimal(dwarf, into: &output)
    }
    if let role = ABI.role(register)?.name {
      append("\" generic=\"", into: &output)
      append(role, into: &output)
    }
    relation(register.relations.containers, name: " value_regnums=\"",
             description: description, compatibility: compatibility,
             into: &output)
    relation(register.relations.invalidates, name: " invalidate_regnums=\"",
             description: description, compatibility: compatibility,
             into: &output)
    append("\"/>", into: &output)
  }

  private mutating func relation(_ range: Range<Int>, name: StaticString,
                                 description: RegisterDescription,
                                 compatibility: CompatibilityMode,
                                 into output: inout OutputSpan<UInt8>) {
    guard !range.isEmpty else {
      return
    }
    append("\"", into: &output)
    append(name, into: &output)
    var separator = false
    for index in range {
      guard let identifier = description.relation(index),
          let register = description.register(identifier),
          let number = description.number(register,
                                          compatibility: compatibility) else {
        continue
      }
      if separator {
        append(",", into: &output)
      }
      decimal(number, into: &output)
      separator = true
    }
  }
}
