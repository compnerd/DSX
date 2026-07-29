// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SavedRegisters: Sendable {
  internal let identifier: UInt64
  internal let thread: ProcessThreadIdentifier
  internal let bytes: Array<UInt8>
  internal let configuration: RegisterConfiguration

  internal init(identifier: UInt64, thread: ProcessThreadIdentifier,
                bytes: consuming Array<UInt8>,
                configuration: RegisterConfiguration =
                    RegisterConfiguration()) {
    self.identifier = identifier
    self.thread = thread
    self.bytes = consume bytes
    self.configuration = configuration
  }
}

extension SavedRegisters {
  @inline(__always)
  internal init(_ thread: ProcessThreadIdentifier, identifier: UInt64)
      throws(Debuggee.Error) {
    try NativeRegisterState.synchronize(thread)
    let snapshot = try NativeRegisterState(thread)
    let description = RegisterDescription(snapshot.configuration)
    var size = NativeRegisterState.checkpoint
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .some = record.numbers.gdb else {
        continue
      }
      size += record.bytes
    }
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: size) { output throws(Debuggee.Error) in
      for index in 0 ..< description.count {
        guard let record = description.register(index),
            case .some = record.numbers.gdb else {
          continue
        }
        try snapshot.read(record.identifier, into: &output)
      }
      try snapshot.checkpoint(into: &output)
    }
    self.init(identifier: identifier, thread: thread, bytes: bytes,
              configuration: snapshot.configuration)
  }
}

extension NativeRegisterState {
  @inline(__always)
  internal mutating func restore(_ saved: borrowing SavedRegisters)
      throws(Debuggee.Error) {
    let description = RegisterDescription(saved.configuration)
    var offset = 0
    for index in 0 ..< description.count {
      guard let record = description.register(index),
          case .some = record.numbers.gdb else {
        continue
      }
      let size = record.bytes
      guard offset <= saved.bytes.count,
          size <= saved.bytes.count - offset else {
        throw .register
      }
      let bytes = saved.bytes.span.extracting(offset ..< (offset + size))
      try write(record.identifier, bytes: bytes)
      offset += size
    }
    try checkpoint(saved.bytes.span.extracting(offset...))
  }
}
