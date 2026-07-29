// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ExpeditedRegisterValue: Sendable {
  internal let number: Int
  internal let value: UInt64
  internal let size: Int
}

internal struct SavedRegisters: Sendable {
  internal let identifier: UInt64
  internal let thread: ProcessThreadIdentifier
  internal let bytes: Array<UInt8>

  internal init(identifier: UInt64, thread: ProcessThreadIdentifier,
                bytes: consuming Array<UInt8>) {
    self.identifier = identifier
    self.thread = thread
    self.bytes = consume bytes
  }
}

extension DebugSession {
  internal typealias RegisterState = NativeRegisters.State

  internal func expedited(_ thread: ProcessThreadIdentifier,
                          compatibility: CompatibilityMode)
      throws(Debuggee.Error) -> InlineArray<3, ExpeditedRegisterValue?> {
    let snapshot = try NativeRegisters.snapshot(thread)
    let description = RegisterDescription()
    var values = InlineArray<3, ExpeditedRegisterValue?> { _ in nil }
    var count = 0
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          record.role?.expedited == true,
          let number =
              description.number(record, compatibility: compatibility),
          count < values.count else {
        continue
      }
      let contents = try value(record, snapshot: snapshot)
      values[count] = ExpeditedRegisterValue(number: number,
                                             value: contents.value,
                                             size: contents.size)
      count += 1
    }
    return values
  }

  internal func program(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    let snapshot = try NativeRegisters.snapshot(thread)
    let description = RegisterDescription()
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .program = record.role else {
        continue
      }
      return try value(record, snapshot: snapshot).value
    }
    throw .register
  }

  internal func program(_ thread: ProcessThreadIdentifier, value: UInt64)
      throws(Debuggee.Error) {
    var snapshot = try NativeRegisters.snapshot(thread)
    let description = RegisterDescription()
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .program = record.role else {
        continue
      }
      let size = try size(record)
      var bytes: InlineArray<8, UInt8> = [0, 0, 0, 0, 0, 0, 0, 0]
      switch ABI.endian {
      case .little:
        for index in 0 ..< size {
          bytes[index] = UInt8(truncatingIfNeeded: value >> (index * 8))
        }
      case .big:
        for index in 0 ..< size {
          bytes[size - index - 1] =
              UInt8(truncatingIfNeeded: value >> (index * 8))
        }
      }
      try NativeRegisters.write(&snapshot, register: record.identifier,
                                bytes: bytes.span.extracting(..<size))
      return try NativeRegisters.commit(snapshot, thread: thread)
    }
    throw .register
  }

  internal mutating func save(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    try NativeRegisters.synchronize(thread)
    let snapshot = try NativeRegisters.snapshot(thread)
    let description = RegisterDescription()
    var size = 0
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .some = record.numbers.gdb else {
        continue
      }
      size += (record.bits + 7) / 8
    }
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: size) { output throws(Debuggee.Error) in
      for index in 0 ..< description.count {
        guard let record = description.register(index),
            case .some = record.numbers.gdb else {
          continue
        }
        try NativeRegisters.read(snapshot, register: record.identifier,
                                 into: &output)
      }
    }
    guard sequence < UInt32.max else {
      throw .state
    }
    sequence += 1
    let identifier = UInt64(sequence)
    snapshots.append(SavedRegisters(identifier: identifier, thread: thread,
                                    bytes: bytes))
    return identifier
  }

  internal mutating func restore(_ identifier: UInt64,
                                 thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    guard let index = snapshots.firstIndex(where: { snapshot in
      snapshot.identifier == identifier
    }) else {
      throw .register
    }
    let saved = snapshots.remove(at: index)
    let identifier = thread ?? saved.thread
    var snapshot = try NativeRegisters.snapshot(identifier)
    let description = RegisterDescription()
    var offset = 0
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .some = record.numbers.gdb else {
        continue
      }
      let size = (record.bits + 7) / 8
      guard offset <= saved.bytes.count,
          size <= saved.bytes.count - offset else {
        throw .register
      }
      let bytes = saved.bytes.span.extracting(offset ..< (offset + size))
      try NativeRegisters.write(&snapshot, register: record.identifier,
                                bytes: bytes)
      offset += size
    }
    guard offset == saved.bytes.count else {
      throw .register
    }
    try NativeRegisters.commit(snapshot, thread: identifier)
  }

  private func size(_ register: RegisterRecord) throws(Debuggee.Error) -> Int {
    let size = (register.bits + 7) / 8
    guard size <= MemoryLayout<UInt64>.size else {
      throw .register
    }
    return size
  }

  private func value(_ register: RegisterRecord,
                     snapshot: borrowing RegisterState)
      throws(Debuggee.Error) -> (value: UInt64, size: Int) {
    let size = try size(register)
    let result =
        try withUnsafePointer(to: snapshot, { state throws(Debuggee.Error) in
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                        { data throws(Debuggee.Error) in
        var output = OutputSpan(buffer: data, initializedCount: 0)
        try NativeRegisters.read(state.pointee, register: register.identifier,
                                 into: &output)
        guard output.count == size else {
          throw .register
        }
        return value(output.span)
      })
    })
    return (result, size)
  }

  private func value(_ bytes: borrowing Span<UInt8>) -> UInt64 {
    var value: UInt64 = 0
    switch ABI.endian {
    case .little:
      for index in 0 ..< bytes.count {
        value |= UInt64(bytes[index]) << UInt64(index * 8)
      }
    case .big:
      for index in 0 ..< bytes.count {
        value = value << 8 | UInt64(bytes[index])
      }
    }
    return value
  }
}
