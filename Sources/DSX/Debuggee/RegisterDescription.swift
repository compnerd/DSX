// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct RegisterIdentifier: Equatable, Sendable {
  internal let rawValue: UInt32

  internal init(rawValue: UInt32) {
    self.rawValue = rawValue
  }
}

internal struct RegisterText: Sendable {
  private let storage: StaticString
  private let range: UInt64

  internal init(storage: StaticString, range: UInt64) {
    self.storage = storage
    self.range = range
  }

  internal var count: Int {
    Int(UInt32(truncatingIfNeeded: range >> 32))
  }

  internal func bytes(_ body: (borrowing Span<UInt8>) -> Void) {
    let offset = Int(UInt32(truncatingIfNeeded: range))
    storage.withUTF8Buffer { storage in
      let bytes =
          UnsafeBufferPointer(rebasing: storage[offset ..< (offset + count)])
      body(bytes.span)
    }
  }
}

internal struct RegisterSetIdentifier: Equatable, Sendable {
  internal let rawValue: UInt16

  internal init(rawValue: UInt16) {
    self.rawValue = rawValue
  }
}

internal enum RegisterEncoding: Sendable {
  case flags
  case ieee
  case signed
  case unsigned
  case vector
}

internal enum RegisterFormat: Sendable {
  case binary
  case decimal
  case float
  case hexadecimal
  case vector
}

internal enum RegisterRole: Sendable {
  case argument(UInt8)
  case flags
  case frame
  case link
  case program
  case result
  case stack
  case thread

  @_transparent
  internal var expedited: Bool {
    switch self {
    case .frame, .program, .stack: true
    case .argument, .flags, .link, .result, .thread: false
    }
  }
}

internal struct RegisterNumbering: Sendable {
  private let value: UInt64

  internal init(rawValue: UInt64) {
    value = rawValue
  }

  internal var gdb: Int? {
    number(bias: 0)
  }

  internal var lldb: Int? {
    number(bias: 16)
  }

  internal var dwarf: Int? {
    number(bias: 32)
  }

  internal var ehframe: Int? {
    number(bias: 48)
  }

  private func number(bias: UInt64) -> Int? {
    let raw = Int16(bitPattern: UInt16(truncatingIfNeeded: value >> bias))
    return if raw > Int16.min {
      Int(raw)
    } else {
      nil
    }
  }
}

internal struct RegisterFeatureIdentifier: Equatable, Sendable {
  internal let rawValue: UInt16

  internal init(rawValue: UInt16) {
    self.rawValue = rawValue
  }
}

internal struct RegisterTypeIdentifier: Equatable, Sendable {
  internal let rawValue: UInt16

  internal init(rawValue: UInt16) {
    self.rawValue = rawValue
  }
}

internal enum RegisterTypeKind: Sendable {
  case `enum`
  case flags
  case vector
}

internal struct RegisterFieldRecord: Sendable {
  internal let name: StaticString
  internal let start: Int
  private let detail: UInt64

  internal var end: Int {
    Int(UInt32(truncatingIfNeeded: detail))
  }

  internal var type: RegisterTypeIdentifier? {
    let encoded = UInt16(truncatingIfNeeded: detail >> 32)
    return if encoded > 0 {
      RegisterTypeIdentifier(rawValue: encoded - 1)
    } else {
      nil
    }
  }

  internal init(name: StaticString, start: Int, end: Int,
                type: RegisterTypeIdentifier?) {
    self.name = name
    self.start = start
    let encoded = type.map { UInt64($0.rawValue) + 1 } ?? 0
    detail = UInt64(UInt32(truncatingIfNeeded: end)) | encoded << 32
  }
}

internal struct RegisterTypeRecord: Sendable {
  internal let identifier: RegisterTypeIdentifier
  internal let feature: RegisterFeatureIdentifier
  internal let name: StaticString
  internal let kind: RegisterTypeKind
  internal let bits: Int?
  internal let element: StaticString?
  internal let count: Int?
  internal let fields: Range<Int>

  internal init(identifier: RegisterTypeIdentifier,
                feature: RegisterFeatureIdentifier, name: StaticString,
                kind: RegisterTypeKind, bits: Int?, element: StaticString?,
                count: Int?, fields: Range<Int>) {
    self.identifier = identifier
    self.feature = feature
    self.name = name
    self.kind = kind
    self.bits = bits
    self.element = element
    self.count = count
    self.fields = fields
  }
}

internal struct RegisterSetRecord: Sendable {
  internal let identifier: RegisterSetIdentifier
  internal let name: StaticString

  internal init(identifier: RegisterSetIdentifier, name: StaticString) {
    self.identifier = identifier
    self.name = name
  }
}

internal struct RegisterFeatureRecord: Sendable {
  internal let identifier: RegisterFeatureIdentifier
  internal let name: StaticString
  internal let includes: Range<Int>

  internal init(identifier: RegisterFeatureIdentifier, name: StaticString,
                includes: Range<Int>) {
    self.identifier = identifier
    self.name = name
    self.includes = includes
  }
}

internal struct RegisterRelations: Sendable {
  private let container: Range<UInt16>
  private let invalidation: Range<UInt16>

  internal init(container: Range<UInt16>, invalidation: Range<UInt16>) {
    self.container = container
    self.invalidation = invalidation
  }

  internal init(rawValue: UInt64) {
    let container = UInt16(truncatingIfNeeded: rawValue)
    let containers = UInt16(truncatingIfNeeded: rawValue >> 16)
    let invalidation = UInt16(truncatingIfNeeded: rawValue >> 32)
    let invalidations = UInt16(truncatingIfNeeded: rawValue >> 48)
    self.container = container ..< containers
    self.invalidation = invalidation ..< invalidations
  }

  internal var containers: Range<Int> {
    Int(container.lowerBound) ..< Int(container.upperBound)
  }

  internal var invalidates: Range<Int> {
    Int(invalidation.lowerBound) ..< Int(invalidation.upperBound)
  }
}

internal struct RegisterStorage: Sendable {
  private let metadata: UInt64
  private let location: UInt64
  private let numbersraw: UInt64
  private let relationsraw: UInt64

  internal init(_ metadata: UInt64, _ location: UInt64, _ numbers: UInt64,
                relations: UInt64) {
    self.metadata = metadata
    self.location = location
    numbersraw = numbers
    relationsraw = relations
  }

  internal var identifier: RegisterIdentifier {
    let value = UInt16(truncatingIfNeeded: metadata)
    return RegisterIdentifier(rawValue: UInt32(value))
  }

  internal var set: RegisterSetIdentifier {
    RegisterSetIdentifier(rawValue: UInt16(truncatingIfNeeded: metadata >> 16))
  }

  internal var role: RegisterRole? {
    let value = UInt8(truncatingIfNeeded: metadata >> 32)
    return if value & 0x80 > 0 {
      .argument(value & 0x7f)
    } else {
      switch value {
      case 0: nil
      case 1: .flags
      case 2: .frame
      case 3: .link
      case 4: .program
      case 5: .result
      case 6: .stack
      case 7: .thread
      default: preconditionFailure("invalid register role")
      }
    }
  }

  internal var bits: UInt16 {
    UInt16(truncatingIfNeeded: location)
  }

  internal var offset: UInt16 {
    UInt16(truncatingIfNeeded: location >> 16)
  }

  internal var type: RegisterTypeIdentifier? {
    let value = UInt16(truncatingIfNeeded: location >> 32)
    return if value < UInt16.max {
      RegisterTypeIdentifier(rawValue: value)
    } else {
      nil
    }
  }

  internal var encoding: RegisterEncoding {
    switch UInt8(truncatingIfNeeded: metadata >> 40) & 0x0f {
    case 0: .flags
    case 1: .ieee
    case 2: .signed
    case 3: .unsigned
    case 4: .vector
    default: preconditionFailure("invalid register encoding")
    }
  }

  internal var format: RegisterFormat {
    switch UInt8(truncatingIfNeeded: metadata >> 44) & 0x0f {
    case 0: .binary
    case 1: .decimal
    case 2: .float
    case 3: .hexadecimal
    case 4: .vector
    default: preconditionFailure("invalid register format")
    }
  }

  internal var numbers: RegisterNumbering {
    RegisterNumbering(rawValue: numbersraw)
  }

  internal var feature: RegisterFeatureIdentifier {
    let value = UInt16(truncatingIfNeeded: metadata >> 48)
    return RegisterFeatureIdentifier(rawValue: value)
  }

  internal var relations: RegisterRelations {
    RegisterRelations(rawValue: relationsraw)
  }
}

internal struct RegisterRecord: Sendable {
  private let storage: RegisterStorage
  internal let index: Int

  internal init(storage: RegisterStorage, index: Int) {
    self.storage = storage
    self.index = index
  }

  internal var identifier: RegisterIdentifier {
    storage.identifier
  }

  internal var set: RegisterSetIdentifier {
    storage.set
  }

  internal var role: RegisterRole? {
    storage.role
  }

  internal var bits: Int {
    Int(storage.bits)
  }

  internal var offset: Int {
    Int(storage.offset)
  }

  internal var encoding: RegisterEncoding {
    storage.encoding
  }

  internal var format: RegisterFormat {
    storage.format
  }

  internal var numbers: RegisterNumbering {
    storage.numbers
  }

  internal var feature: RegisterFeatureIdentifier {
    storage.feature
  }

  internal var type: RegisterTypeIdentifier? {
    storage.type
  }

  internal var relations: RegisterRelations {
    storage.relations
  }
}

extension RegisterDescription {
  internal func register(_ identifier: RegisterIdentifier) -> RegisterRecord? {
    for index in 0 ..< count {
      guard let register = register(index) else {
        continue
      }
      if register.identifier == identifier {
        return register
      }
    }
    return nil
  }

  internal func register(_ number: Int, compatibility: CompatibilityMode)
      -> RegisterRecord? {
    for index in 0 ..< count {
      guard let register = register(index) else {
        continue
      }
      let candidate = switch compatibility {
      case .gdb: register.numbers.gdb
      case .lldb: register.numbers.lldb
      }
      if candidate == number {
        return register
      }
    }
    return nil
  }

  internal func number(_ register: RegisterRecord,
                       compatibility: CompatibilityMode) -> Int? {
    switch compatibility {
    case .gdb: register.numbers.gdb
    case .lldb: register.numbers.lldb
    }
  }

  internal func size(_ compatibility: CompatibilityMode) -> Int {
    var size = 0
    for index in 0 ..< count {
      guard let register = register(index),
          case .some = register.numbers.gdb else {
        continue
      }
      size += (register.bits + 7) / 8
    }
    return size
  }
}
