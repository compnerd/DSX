// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal func validate(_ profile: RegisterProfileDefinition)
    throws(DSXCodeGenError) {
  guard identifier(profile.profile) else {
    throw .schema("profile name is not a Swift identifier")
  }
  guard identifier(profile.architecture) else {
    throw .schema("architecture is not a Swift architecture name")
  }
  guard profile.layout == .fixed else {
    throw .schema("scalable register profiles are not implemented")
  }
  guard !profile.sets.isEmpty else {
    throw .schema("profile has no register sets")
  }
  guard !profile.features.isEmpty else {
    throw .schema("profile has no GDB features")
  }
  guard !profile.registers.isEmpty else {
    throw .schema("profile has no registers")
  }

  try unique(profile.sets.map { ($0.id, $0.platforms) },
             label: "register set identifier")
  try unique(profile.sets.map(\.name), label: "register set name")
  try unique(profile.features.map(\.id), label: "feature identifier")
  try unique(profile.features.map(\.name), label: "feature name")
  try availability(profile.sets.map(\.platforms), label: "register set")
  try availability(profile.features.map(\.platforms), label: "feature")
  try availability(profile.registers.map(\.platforms), label: "register")
  let types = profile.features.flatMap(\.types)
  try unique(types.map(\.name), label: "GDB type name")
  try unique(profile.registers.map(\.id), label: "register identifier")
  try unique(profile.registers.map(\.name), label: "register name")
  let relations = profile.registers.reduce(0) { count, register in
    let containers = register.relations.containers.count
    let invalidates = register.relations.invalidates.count
    return count + containers + invalidates
  }
  guard relations <= Int(UInt16.max) else {
    throw .schema("profile has too many register relations")
  }

  let sets = Set(profile.sets.map(\.name))
  let features = Set(profile.features.map(\.name))
  let registers = Set(profile.registers.map(\.name))
  let records = Dictionary(uniqueKeysWithValues: profile.registers.map {
      ($0.name, $0)
  })
  let custom = Set(types.map(\.name))
  let enumerations = Set(types.filter { $0.kind == .enum }.map(\.name))
  let builtin: Set<String> = [
    "code_ptr", "data_ptr", "float", "double", "i387_ext",
    "int8", "int16", "int32", "int64", "int128",
    "uint8", "uint16", "uint32", "uint64", "uint128",
  ]
  for type in types {
    try validate(type)
    for field in type.fields {
      if let name = field.type {
        if enumerations.contains(name) {
          continue
        }
        throw .schema("field '\(field.name)' has an unknown enum type")
      }
    }
  }
  for register in profile.registers {
    guard register.id <= UInt32(UInt16.max) else {
      throw .schema("register '\(register.name)' has an invalid identifier")
    }
    guard register.bits > 0 && register.bits.isMultiple(of: 8) else {
      throw .schema("register '\(register.name)' has an invalid size")
    }
    guard register.bits <= Int(UInt16.max) else {
      throw .schema("register '\(register.name)' is too wide")
    }
    guard register.offset >= 0 && register.offset <= Int(UInt16.max) else {
      throw .schema("register '\(register.name)' has an invalid offset")
    }
    guard sets.contains(register.set) else {
      throw .schema("register '\(register.name)' has an unknown set")
    }
    guard features.contains(register.feature) else {
      throw .schema("register '\(register.name)' has an unknown feature")
    }
    if let type = register.type {
      guard builtin.contains(type) || custom.contains(type) else {
        throw .schema("register '\(register.name)' has an unknown GDB type")
      }
    }
    let targets = register.relations.containers + register.relations.invalidates
    for target in targets {
      guard registers.contains(target) else {
        throw .schema("register '\(register.name)' has an unknown relation")
      }
    }
    let child = register.offset ..< (register.offset + register.bits / 8)
    for name in register.relations.containers {
      if name == register.name {
        throw .schema("register '\(register.name)' has an invalid container")
      }
      guard let record = records[name] else {
        throw .schema("register '\(register.name)' has an invalid container")
      }
      let parent = record.offset ..< (record.offset + record.bits / 8)
      guard parent.lowerBound <= child.lowerBound &&
          parent.upperBound >= child.upperBound else {
        throw .schema("register '\(register.name)' has an invalid container")
      }
    }
  }

  try numbers(profile.registers, key: \.numbers.gdb, label: "GDB")
  try numbers(profile.registers, key: \.numbers.lldb, label: "LLDB")
  try numbers(profile.registers, key: \.numbers.dwarf, label: "DWARF")
  try numbers(profile.registers, key: \.numbers.ehframe, label: "EH-frame")
  try roles(profile.registers)
  try storage(profile.registers)
  try includes(profile.features)
}

private func identifier(_ value: String) -> Bool {
  guard let first = value.first, first.isLetter || first == "_" else {
    return false
  }
  return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
}

private func validate(_ type: RegisterTypeDefinition) throws(DSXCodeGenError) {
  switch type.kind {
  case .enum:
    guard let bits = type.bits, bits > 0, bits.isMultiple(of: 8),
        case .none = type.element, case .none = type.count else {
      throw .schema("enum type '\(type.name)' has invalid metadata")
    }
    guard !type.fields.isEmpty else {
      throw .schema("enum type '\(type.name)' has no values")
    }
    try unique(type.fields.map(\.name), label: "enum value name")
    try unique(type.fields.map(\.start), label: "enum value")
    for field in type.fields {
      guard field.start >= 0, field.start == field.end,
          case .none = field.type else {
        throw .schema("enum type '\(type.name)' has an invalid value")
      }
    }
  case .flags:
    guard let bits = type.bits, bits > 0, bits.isMultiple(of: 8),
        case .none = type.element, case .none = type.count else {
      throw .schema("flag type '\(type.name)' has invalid metadata")
    }
    guard !type.fields.isEmpty else {
      throw .schema("flag type '\(type.name)' has no fields")
    }
    try unique(type.fields.map(\.name), label: "flag field name")
    for field in type.fields {
      guard field.start >= 0 && field.start <= field.end &&
          field.end < bits else {
        throw .schema("flag type '\(type.name)' has an invalid field")
      }
    }
  case .vector:
    guard case .none = type.bits, let count = type.count, count > 0,
        let element = type.element, !element.isEmpty, type.fields.isEmpty else {
      throw .schema("vector type '\(type.name)' has invalid metadata")
    }
  }
}

private func unique<T>(_ values: Array<T>, label: String)
    throws(DSXCodeGenError) where T: Hashable {
  guard Set(values).count == values.count else {
    throw .schema("duplicate \(label)")
  }
}

private typealias Availability = Array<RegisterPlatform>

private func unique<T: Hashable>(_ values: Array<(T, Availability)>,
                                 label: String) throws(DSXCodeGenError) {
  var records = Dictionary<T, Array<Set<RegisterPlatform>>>()
  for (value, platforms) in values {
    let condition = Set(platforms)
    for existing in records[value, default: []] {
      guard !existing.isEmpty, !condition.isEmpty,
          existing.isDisjoint(with: condition) else {
        throw .schema("duplicate \(label)")
      }
    }
    records[value, default: []].append(condition)
  }
}

private func availability(_ values: Array<Array<RegisterPlatform>>,
                          label: String) throws(DSXCodeGenError) {
  var conditions = Array<Set<RegisterPlatform>>()
  for value in values {
    guard !value.isEmpty else {
      continue
    }
    let condition = Set(value)
    guard condition.count == value.count else {
      throw .schema("conditional \(label) has duplicate platforms")
    }
    if conditions.contains(condition) {
      continue
    }
    guard conditions.allSatisfy({ $0.isDisjoint(with: condition) }) else {
      throw .schema("conditional \(label)s have overlapping platforms")
    }
    conditions.append(condition)
  }
}

private func numbers(_ registers: Array<RegisterDefinition>,
                     key: KeyPath<RegisterDefinition, Int?>,
                     label: String) throws(DSXCodeGenError) {
  let values = registers.compactMap { $0[keyPath: key] }
  guard values.allSatisfy({
    $0 > Int(Int16.min) && $0 <= Int(Int16.max)
  }) else {
    throw .schema("\(label) register number is out of range")
  }
  var records = Dictionary<Int, Array<Set<RegisterPlatform>>>()
  for register in registers {
    guard let value = register[keyPath: key] else {
      continue
    }
    let condition = Set(register.platforms)
    for existing in records[value, default: []] {
      guard !existing.isEmpty, !condition.isEmpty,
          existing.isDisjoint(with: condition) else {
        throw .schema("duplicate \(label) register number")
      }
    }
    records[value, default: []].append(condition)
  }
}

private func roles(_ registers: Array<RegisterDefinition>)
    throws(DSXCodeGenError) {
  let roles = registers.compactMap(\.role)
  try unique(roles, label: "generic register role")

}

private func storage(_ registers: Array<RegisterDefinition>)
    throws(DSXCodeGenError) {
  for first in registers.indices {
    let lhs = registers[first]
    let range = lhs.offset ..< (lhs.offset + lhs.bits / 8)
    for second in registers.indices where second > first {
      let rhs = registers[second]
      let candidate = rhs.offset ..< (rhs.offset + rhs.bits / 8)
      guard range.overlaps(candidate) else {
        continue
      }
      let platforms = Set(lhs.platforms).intersection(rhs.platforms)
      if lhs.platforms.count > 0, rhs.platforms.count > 0, platforms.isEmpty {
        continue
      }
      let related =
          lhs.relations.containers.contains(rhs.name) ||
          lhs.relations.invalidates.contains(rhs.name) ||
          rhs.relations.containers.contains(lhs.name) ||
          rhs.relations.invalidates.contains(lhs.name)
      guard related else {
        throw .schema("register storage overlaps without a relation: " +
                      "'\(lhs.name)' and '\(rhs.name)'")
      }
    }
  }
}

private func includes(_ features: Array<RegisterFeatureDefinition>)
    throws(DSXCodeGenError) {
  let names = Set(features.map(\.name))
  let graph = Dictionary(uniqueKeysWithValues: features.map {
      ($0.name, $0.includes)
  })
  for feature in features {
    for include in feature.includes {
      guard names.contains(include) else {
        throw .schema("feature '\(feature.name)' includes an unknown feature")
      }
    }
  }

  var visited = Set<String>()
  var active = Set<String>()
  func visit(_ name: String) throws(DSXCodeGenError) {
    if active.contains(name) {
      throw .schema("feature include cycle at '\(name)'")
    }
    if visited.contains(name) {
      return
    }
    active.insert(name)
    for include in graph[name] ?? [] {
      try visit(include)
    }
    active.remove(name)
    visited.insert(name)
  }
  for feature in features {
    try visit(feature.name)
  }
}
