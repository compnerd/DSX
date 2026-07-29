// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func emit(_ registers: RegisterDescription, offset: UInt64,
                              length: UInt64, compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    try transfer(offset: offset, length: length) { emitter in
      emitter.emit(registers, compatibility: compatibility)
    }
  }
}

extension GDBTransferEmitter {
  fileprivate mutating func emit(_ description: RegisterDescription,
                                 compatibility: CompatibilityMode) {
    append("<?xml version=\"1.0\"?><!DOCTYPE target SYSTEM ")
    append("\"gdb-target.dtd\"><target><architecture>")
    append(RegisterDescription.architecture)
    append("</architecture>")
    let configuration = description.configuration
    let features = compatibility == .lldb ? 1 : description.features
    for index in 0 ..< features {
      guard let feature = description.feature(index) else {
        continue
      }
      if compatibility == .gdb,
          description.contains(feature.identifier) == false {
        continue
      }
      append("<feature name=\"")
      append(feature.name)
      append("\">")
      for identifier in 0 ..< description.types {
        guard let type = description.type(identifier) else {
          continue
        }
        let owner = configuration.feature(type.feature)
        guard compatibility == .lldb || owner == feature.identifier else {
          continue
        }
        if configuration.count(type) == 0 {
          continue
        }
        emit(type, description: description)
      }
      for number in 0 ..< description.count {
        guard let register =
            description.register(number, compatibility: compatibility) else {
          continue
        }
        let owner = configuration.feature(register.feature)
        guard compatibility == .lldb || owner == feature.identifier else {
          continue
        }
        emit(register, number: number, description: description,
             compatibility: compatibility)
      }
      append("</feature>")
    }
    append("</target>")
  }

  private mutating func emit(_ type: RegisterTypeRecord,
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
            let enumeration = description.type(identifier) {
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
      if let count = description.configuration.count(type) {
        append("\" count=\"")
        decimal(count)
      }
      append("\"/>")
    }
  }

  @inline(never)
  private mutating func emit(_ register: RegisterRecord, number: Int,
                             description: RegisterDescription,
                             compatibility: CompatibilityMode) {
    let name = description.name(register, compatibility: compatibility)
    append("<reg name=\"")
    append(name)
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
    if let name = description.type(register) {
      append("\" type=\"")
      append(name)
    }
    if let group =
        description.group(register.set, compatibility: compatibility) {
      append("\" group=\"")
      append(group)
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
