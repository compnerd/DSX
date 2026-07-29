// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBRegisterFeaturesPacket {
  internal static func write(offset: UInt64, length: UInt64,
                             registers: RegisterDescription,
                             compatibility: CompatibilityMode,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.transfer(offset: offset, length: length) { emitter in
      emitter.write(registers, compatibility: compatibility)
    }
  }
}

extension GDBTransferEmitter {
  fileprivate mutating func write(_ description: RegisterDescription,
                                  compatibility: CompatibilityMode) {
    append("<?xml version=\"1.0\"?><!DOCTYPE target SYSTEM ")
    append("\"gdb-target.dtd\"><target><architecture>")
    append(RegisterDescription.architecture)
    append("</architecture>")
    let features = compatibility == .lldb ? 1 : description.features
    for index in 0 ..< features {
      guard let feature = description.feature(index) else {
        continue
      }
      append("<feature name=\"")
      append(feature.name)
      append("\">")
      for identifier in 0 ..< description.types {
        guard let type = description.type(identifier),
            compatibility == .lldb || type.feature == feature.identifier else {
          continue
        }
        write(type, description: description)
      }
      for number in 0 ..< description.count {
        guard let register =
            description.register(number, compatibility: compatibility),
            compatibility == .lldb ||
              register.feature == feature.identifier else {
          continue
        }
        write(register, number: number, description: description,
              compatibility: compatibility)
      }
      append("</feature>")
    }
    append("</target>")
  }

  private mutating func write(_ type: RegisterTypeRecord,
                              description: RegisterDescription) {
    switch type.kind {
    case .enum:
      append("<enum id=\"")
      append(type.name)
      append("\" size=\"")
      decimal((type.bits ?? 0) / 8)
      append("\">")
      for index in type.fields {
        guard let field = description.field(index) else {
          continue
        }
        append("<evalue name=\"")
        append(field.name)
        append("\" value=\"")
        decimal(field.start)
        append("\"/>")
      }
      append("</enum>")
    case .flags:
      append("<flags id=\"")
      append(type.name)
      append("\" size=\"")
      decimal((type.bits ?? 0) / 8)
      append("\">")
      for index in type.fields {
        guard let field = description.field(index) else {
          continue
        }
        append("<field name=\"")
        append(field.name)
        append("\" start=\"")
        decimal(field.start)
        append("\" end=\"")
        decimal(field.end)
        if let identifier = field.type,
            let enumeration = description.type(Int(identifier.rawValue)) {
          append("\" type=\"")
          append(enumeration.name)
        }
        append("\"/>")
      }
      append("</flags>")
    case .vector:
      append("<vector id=\"")
      append(type.name)
      if let element = type.element {
        append("\" type=\"")
        append(element)
      }
      if let count = type.count {
        append("\" count=\"")
        decimal(count)
      }
      append("\"/>")
    }
  }

  private mutating func write(_ register: RegisterRecord, number: Int,
                              description: RegisterDescription,
                              compatibility: CompatibilityMode) {
    append("<reg name=\"")
    append(description.name(register))
    append("\"")
    if let alias = description.alias(register) {
      append(" altname=\"")
      append(alias)
      append("\"")
    }
    append(" bitsize=\"")
    decimal(register.bits)
    append("\" regnum=\"")
    decimal(number)
    append("\" offset=\"")
    decimal(register.offset)
    append("\" encoding=\"")
    append(register.encoding.name)
    append("\" format=\"")
    append(register.format.name)
    if let identifier = register.type,
        let type = description.type(Int(identifier.rawValue)) {
      append("\" type=\"")
      append(type.name)
    }
    if let set = description.set(Int(register.set.rawValue)) {
      append("\" group=\"")
      append(set.name)
    }
    if let ehframe = register.numbers.ehframe {
      append("\" ehframe_regnum=\"")
      decimal(ehframe)
    }
    if let dwarf = register.numbers.dwarf {
      append("\" dwarf_regnum=\"")
      decimal(dwarf)
    }
    if let role = ABI.role(register)?.name {
      append("\" generic=\"")
      append(role)
    }
    relation(register.relations.containers, name: " value_regnums=\"",
             description: description, compatibility: compatibility)
    relation(register.relations.invalidates, name: " invalidate_regnums=\"",
             description: description, compatibility: compatibility)
    append("\"/>")
  }

  private mutating func relation(_ range: Range<Int>, name: StaticString,
                                 description: RegisterDescription,
                                 compatibility: CompatibilityMode) {
    guard !range.isEmpty else {
      return
    }
    append("\"")
    append(name)
    var separator = false
    for index in range {
      guard let identifier = description.relation(index),
          let register = description.register(identifier),
          let number =
              description.number(register, compatibility: compatibility) else {
        continue
      }
      if separator {
        append(",")
      }
      decimal(number)
      separator = true
    }
  }
}
