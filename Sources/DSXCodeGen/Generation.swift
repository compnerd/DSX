// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GeneratedProfile {
  internal let name: String
  internal let architecture: String
  internal let source: String
}

internal func generate(_ profile: RegisterProfileDefinition)
    -> GeneratedProfile {
  let type = profile.profile + "RegisterDescription"
  let sets = Dictionary(uniqueKeysWithValues: profile.sets.map {
      ($0.name, $0.id)
  })
  let features = Dictionary(uniqueKeysWithValues: profile.features.map {
      ($0.name, $0.id)
  })
  let named = profile.features.flatMap(\.types).enumerated().map {
      ($0.element.name, UInt16($0.offset))
  }
  let identifiers = Dictionary(uniqueKeysWithValues: named)
  let registers = Dictionary(uniqueKeysWithValues: profile.registers.map {
      ($0.name, $0.id)
  })
  var relations = Array<UInt32>()
  var ranges = Array<(Range<Int>, Range<Int>)>()
  for register in profile.registers {
    let containers = relations.count
    relations += register.relations.containers.map { registers[$0]! }
    let invalidates = relations.count
    relations += register.relations.invalidates.map { registers[$0]! }
    ranges.append((containers ..< invalidates, invalidates ..< relations.count))
  }

  var includes = Array<UInt16>()
  var spans = Array<Range<Int>>()
  for feature in profile.features {
    let start = includes.count
    includes += feature.includes.map { features[$0]! }
    spans.append(start ..< includes.count)
  }
  let types = profile.features.flatMap { feature in
    feature.types.map { (feature.id, $0) }
  }
  var fields = Array<RegisterFieldDefinition>()
  var bounds = Array<Range<Int>>()
  for (_, type) in types {
    let start = fields.count
    fields += type.fields
    bounds.append(start ..< fields.count)
  }

  var lines = header()
  lines.append("")
  lines.append("#if arch(\(profile.architecture))")
  lines.append("internal struct \(type): Sendable {")
  lines.append("  internal static let architecture: StaticString = " +
               literal(target(profile.architecture)))
  lines.append("")
  var records = Array<(Array<RegisterPlatform>, Array<String>)>()
  for register in profile.registers {
    let type = register.type.flatMap { identifiers[$0] }
    guard let set = sets[register.set],
        let feature = features[register.feature] else {
      preconditionFailure("invalid register reference")
    }
    let entry = record(register, set: set, feature: feature, type: type)
    records.append((register.platforms, entry))
  }
  lines += array("  internal static let kRecords: " +
                 "InlineArray<_, UInt64> = [", entries: records)
  if relations.count > 0 {
    lines.append("")
    lines += relation(ranges, registers: profile.registers)
  }
  lines.append("")
  lines += strings("Names", values: profile.registers.map {
    (Optional($0.name), $0.platforms)
  })
  lines.append("")
  lines += strings("Aliases", values: profile.registers.map {
    ($0.alternate, $0.platforms)
  })
  lines.append("")
  lines.append("  internal static let kRelations: " +
               "InlineArray<_, RegisterIdentifier> = [")
  for identifier in relations {
    lines.append("    RegisterIdentifier(rawValue: \(identifier)),")
  }
  lines.append("  ]")
  lines.append("")
  records.removeAll(keepingCapacity: true)
  for set in profile.sets {
    let entry = [
      "    RegisterSetRecord(",
      "        identifier: RegisterSetIdentifier(rawValue: \(set.id)),",
      "        name: \(literal(set.title))),",
    ]
    records.append((set.platforms, entry))
  }
  lines += array("  internal static let kSets: " +
                 "InlineArray<_, RegisterSetRecord> = [", entries: records)
  lines.append("")
  records.removeAll(keepingCapacity: true)
  for (index, feature) in profile.features.enumerated() {
    let range = spans[index]
    let value = "\(range.lowerBound) ..< \(range.upperBound)"
    let entry = [
      "    RegisterFeatureRecord(",
      "        identifier: RegisterFeatureIdentifier(rawValue: " +
          "\(feature.id)),",
      "        name: \(literal(feature.name)),",
      "        includes: \(value)),",
    ]
    records.append((feature.platforms, entry))
  }
  lines += array("  internal static let kFeatures: " +
                 "InlineArray<_, RegisterFeatureRecord> = [", entries: records)
  lines.append("")
  lines.append("  internal static let kTypes: " +
               "InlineArray<_, RegisterTypeRecord> = [")
  for (index, entry) in types.enumerated() {
    let range = bounds[index]
    let value = "\(range.lowerBound) ..< \(range.upperBound)"
    lines.append("    RegisterTypeRecord(")
    lines.append("        identifier: RegisterTypeIdentifier(rawValue: " +
                 "\(index)),")
    lines.append("        feature: RegisterFeatureIdentifier(rawValue: " +
                 "\(entry.0)),")
    lines.append("        name: \(literal(entry.1.name)),")
    lines.append("        kind: .\(entry.1.kind.rawValue),")
    lines.append("        bits: \(optional(entry.1.bits)),")
    lines.append("        element: \(optional(entry.1.element)),")
    lines.append("        count: \(optional(entry.1.count)),")
    lines.append("        fields: \(value)),")
  }
  lines.append("  ]")
  lines.append("")
  lines.append("  internal static let kFields: " +
               "InlineArray<_, RegisterFieldRecord> = [")
  for field in fields {
    let type = field.type.flatMap { identifiers[$0] }
    let reference = type.map {
      "RegisterTypeIdentifier(rawValue: \($0))"
    } ?? "nil"
    lines.append("    RegisterFieldRecord(name: \(literal(field.name)),")
    lines.append("                        start: \(field.start),")
    lines.append("                        end: \(field.end),")
    lines.append("                        type: \(reference)),")
  }
  lines.append("  ]")
  lines.append("")
  lines.append("  internal static let kIncludes: " +
               "InlineArray<_, RegisterFeatureIdentifier> = [")
  for identifier in includes {
    lines.append("    RegisterFeatureIdentifier(rawValue: \(identifier)),")
  }
  lines.append("  ]")
  lines.append("")
  lines += accessors(type, relations: relations.count > 0)
  lines.append("}")
  lines.append("#endif")
  lines.append("")
  return GeneratedProfile(name: type, architecture: profile.architecture,
                          source: lines.joined(separator: "\n"))
}

private func target(_ architecture: String) -> String {
  switch architecture {
  case "arm64": "aarch64"
  case "riscv64": "riscv:rv64"
  case "x86_64": "i386:x86-64"
  default: architecture
  }
}

internal func registry(_ profiles: Array<GeneratedProfile>) -> String {
  var lines = header()
  lines.append("")
  for profile in profiles {
    lines.append("#if arch(\(profile.architecture))")
    lines.append("internal typealias RegisterDescription = \(profile.name)")
    lines.append("#endif")
  }
  lines.append("")
  return lines.joined(separator: "\n")
}

internal func header() -> Array<String> {
  [
    "// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. " +
        "All rights reserved.",
    "// SPDX-License-Identifier: BSD-3-Clause",
    "",
    "// Generated by DSXCodeGen. Do not edit.",
  ]
}

private func record(_ register: RegisterDefinition, set: UInt16,
                    feature: UInt16, type: UInt16?) -> Array<String> {
  let identity = UInt64(register.id) | UInt64(set) << 16
  let encoded = UInt64(encoding(register.encoding)) << 40
  let formatted = UInt64(format(register.format)) << 44
  let semantics = UInt64(role(register.role)) << 32 | encoded | formatted
  let metadata = identity | semantics | UInt64(feature) << 48
  let type = type ?? UInt16.max
  let location = UInt64(register.bits) | UInt64(register.offset) << 16
               | UInt64(type) << 32
  let low = UInt64(number(register.numbers.gdb))
          | UInt64(number(register.numbers.lldb)) << 16
  let high = UInt64(number(register.numbers.dwarf)) << 32
           | UInt64(number(register.numbers.ehframe)) << 48
  let numbers = low | high
  return [metadata, location, numbers].map { value in
    "    0x\(String(value, radix: 16)),"
  }
}

private func relation(_ ranges: Array<(Range<Int>, Range<Int>)>,
                      registers: Array<RegisterDefinition>) -> Array<String> {
  var lines = [
    "  private static func relations(_ index: Int) -> UInt64 {",
  ]
  let conditions = conditions(registers.map(\.platforms))
  if conditions.isEmpty {
    lines += emit(ranges.indices.map { ($0, $0) }, ranges: ranges)
  } else {
    for (index, condition) in conditions.enumerated() {
      let directive = if index == 0 {
        "#if \(expression(condition))"
      } else {
        "#elseif \(expression(condition))"
      }
      lines.append(directive)
      let selected = registers.indices.filter {
        registers[$0].platforms.isEmpty ||
            Set(registers[$0].platforms) == Set(condition)
      }
      let indices = selected.enumerated().map { ($0.offset, $0.element) }
      lines += emit(indices, ranges: ranges)
    }
    lines.append("#else")
    let selected = registers.indices.filter { registers[$0].platforms.isEmpty }
    let indices = selected.enumerated().map { ($0.offset, $0.element) }
    lines += emit(indices, ranges: ranges)
    lines.append("#endif")
  }
  lines.append("  }")
  return lines
}

private func emit(_ indices: Array<(Int, Int)>,
                  ranges: Array<(Range<Int>, Range<Int>)>) -> Array<String> {
  var lines = ["    switch index {"]
  for (local, source) in indices {
    let containers = ranges[source].0
    let invalidates = ranges[source].1
    guard !containers.isEmpty || !invalidates.isEmpty else {
      continue
    }
    let low = UInt64(containers.lowerBound)
            | UInt64(containers.upperBound) << 16
    let high = UInt64(invalidates.lowerBound) << 32
             | UInt64(invalidates.upperBound) << 48
    let value = low | high
    lines.append("    case \(local): 0x\(String(value, radix: 16))")
  }
  lines.append("    default: 0")
  lines.append("    }")
  return lines
}

private func expression(_ platforms: Array<RegisterPlatform>) -> String {
  let values = platforms.map { platform in
    switch platform {
    case .android: "os(Android)"
    case .apple: "os(anyAppleOS)"
    case .linux: "os(Linux)"
    }
  }
  return values.joined(separator: " || ")
}

private func array(_ declaration: String,
                   entries: Array<(Array<RegisterPlatform>, Array<String>)>)
    -> Array<String> {
  let groups = conditions(entries.map(\.0))
  guard !groups.isEmpty else {
    return [declaration] + entries.flatMap(\.1) + ["  ]"]
  }
  var lines = Array<String>()
  for (index, group) in groups.enumerated() {
    let directive = if index == 0 {
      "#if \(expression(group))"
    } else {
      "#elseif \(expression(group))"
    }
    lines.append(directive)
    lines.append(declaration)
    for entry in entries where entry.0.isEmpty || Set(entry.0) == Set(group) {
      lines += entry.1
    }
    lines.append("  ]")
  }
  lines += ["#else", declaration]
  for entry in entries where entry.0.isEmpty {
    lines += entry.1
  }
  lines += ["  ]", "#endif"]
  return lines
}

private func conditions(_ values: Array<Array<RegisterPlatform>>)
    -> Array<Array<RegisterPlatform>> {
  var result = Array<Array<RegisterPlatform>>()
  for value in values where value.count > 0 {
    if result.contains(where: { Set($0) == Set(value) }) {
      continue
    }
    result.append(value)
  }
  return result
}

private func strings(_ name: String,
                     values: Array<(String?, Array<RegisterPlatform>)>)
    -> Array<String> {
  var lines = Array<String>()
  let groups = conditions(values.map(\.1))
  if groups.isEmpty {
    lines += storage(name, values: values.map(\.0))
  } else {
    for (index, group) in groups.enumerated() {
      let directive = if index == 0 {
        "#if \(expression(group))"
      } else {
        "#elseif \(expression(group))"
      }
      lines.append(directive)
      lines += storage(name, values: values.filter {
        $0.1.isEmpty || Set($0.1) == Set(group)
      }.map(\.0))
    }
    lines.append("#else")
    lines += storage(name, values: values.filter(\.1.isEmpty).map(\.0))
    lines.append("#endif")
  }
  return lines
}

private func storage(_ name: String, values: Array<String?>) -> Array<String> {
  let storage = values.compactMap { $0 }.joined()
  var lines = [
    "  private static let k\(name): StaticString = \(literal(storage))",
    "  private static let k\(name)Ranges: InlineArray<_, UInt64> = [",
  ]
  var offset = 0
  for value in values {
    guard let value else {
      lines.append("    UInt64.max,")
      continue
    }
    let count = value.utf8.count
    let range = UInt64(offset) | UInt64(count) << 32
    lines.append("    0x\(String(range, radix: 16)),")
    offset += count
  }
  lines.append("  ]")
  return lines
}

private func accessors(_ type: String, relations: Bool) -> Array<String> {
  let relations = relations ? "\(type).relations(index)" : "0"
  return [
    "  internal var count: Int { \(type).kRecords.count / 3 }",
    "  internal var sets: Int { \(type).kSets.count }",
    "  internal var features: Int { \(type).kFeatures.count }",
    "  internal var types: Int { \(type).kTypes.count }",
    "  internal var fields: Int { \(type).kFields.count }",
    "",
    "  internal func register(_ index: Int) -> RegisterRecord? {",
    "    guard index >= 0 && index < count else {",
    "      return nil",
    "    }",
    "    let base = index * 3",
    "    let storage = RegisterStorage(\(type).kRecords[base],",
    "                                  \(type).kRecords[base + 1],",
    "                                  \(type).kRecords[base + 2],",
    "                                  relations: \(relations))",
    "    return RegisterRecord(storage: storage, index: index)",
    "  }",
    "",
    "  internal func name(_ register: RegisterRecord) -> RegisterText {",
    "    RegisterText(storage: \(type).kNames,",
    "                 range: \(type).kNamesRanges[register.index])",
    "  }",
    "",
    "  internal func alias(_ register: RegisterRecord) -> RegisterText? {",
    "    let range = \(type).kAliasesRanges[register.index]",
    "    if range == UInt64.max {",
    "      return nil",
    "    }",
    "    return RegisterText(storage: \(type).kAliases, range: range)",
    "  }",
    "",
    "  internal func relation(_ index: Int) -> RegisterIdentifier? {",
    "    guard index >= 0 && index < \(type).kRelations.count else {",
    "      return nil",
    "    }",
    "    return \(type).kRelations[index]",
    "  }",
    "",
    "  internal func set(_ index: Int) -> RegisterSetRecord? {",
    "    guard index >= 0 && index < \(type).kSets.count else {",
    "      return nil",
    "    }",
    "    return \(type).kSets[index]",
    "  }",
    "",
    "  internal func feature(_ index: Int) -> RegisterFeatureRecord? {",
    "    guard index >= 0 && index < \(type).kFeatures.count else {",
    "      return nil",
    "    }",
    "    return \(type).kFeatures[index]",
    "  }",
    "",
    "  internal func include(_ index: Int) " +
        "-> RegisterFeatureIdentifier? {",
    "    guard index >= 0 && index < \(type).kIncludes.count else {",
    "      return nil",
    "    }",
    "    return \(type).kIncludes[index]",
    "  }",
    "",
    "  internal func type(_ index: Int) -> RegisterTypeRecord? {",
    "    guard index >= 0 && index < \(type).kTypes.count else {",
    "      return nil",
    "    }",
    "    return \(type).kTypes[index]",
    "  }",
    "",
    "  internal func field(_ index: Int) -> RegisterFieldRecord? {",
    "    guard index >= 0 && index < \(type).kFields.count else {",
    "      return nil",
    "    }",
    "    return \(type).kFields[index]",
    "  }",
  ]
}

private func literal(_ value: String) -> String {
  let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}

private func optional(_ value: String?) -> String {
  if let value {
    literal(value)
  } else {
    "nil"
  }
}

private func optional(_ value: Int?) -> String {
  if let value {
    String(value)
  } else {
    "nil"
  }
}

private func number(_ value: Int?) -> UInt16 {
  UInt16(bitPattern: Int16(value ?? Int(Int16.min)))
}

private func role(_ value: RegisterRole?) -> UInt8 {
  guard let value else {
    return 0
  }
  return switch value {
  case .flags: 1
  case .frame: 2
  case .link: 3
  case .program: 4
  case .result: 5
  case .stack: 6
  case .thread: 7
  case .argument(let value): 0x80 | value
  }
}

private func encoding(_ value: RegisterEncoding) -> UInt8 {
  switch value {
  case .flags: 0
  case .ieee: 1
  case .signed: 2
  case .unsigned: 3
  case .vector: 4
  }
}

private func format(_ value: RegisterFormat) -> UInt8 {
  switch value {
  case .binary: 0
  case .decimal: 1
  case .float: 2
  case .hexadecimal: 3
  case .vector: 4
  }
}
