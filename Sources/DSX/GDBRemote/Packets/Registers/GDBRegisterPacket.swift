// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension ProcessThreadIdentifier {
  internal func snapshot() throws(GDBHandlerError) -> NativeRegisterState {
    do {
      return try NativeRegisterState(self)
    } catch {
      DSX.log("failed to read registers for \(self): \(error)", level: .error,
              channel: .process)
      throw .debuggee(error)
    }
  }
}

extension GDBPacketReader {
  internal mutating func apply(to state: inout NativeRegisterState,
                               register: RegisterRecord,
                               model: RegisterDescription,
                               scratch: inout OutputSpan<UInt8>)
      throws(GDBHandlerError) {
    let count = register.bytes
    guard scratch.capacity >= count else {
      throw .capacity
    }
    scratch.removeAll()
    for _ in 0 ..< count {
      let upper = try read()
      let lower = try read()
      guard let high = UInt8(hex: upper), let low = UInt8(hex: lower) else {
        throw .malformed
      }
      scratch.append(high << 4 | low)
    }
    try translate(state.write(register, container: model.container(register),
                              bytes: scratch.span))
    scratch.removeAll()
  }
}

extension RegisterDescription {
  fileprivate func container(_ register: RegisterRecord) -> RegisterRecord? {
    guard register.numbers.gdb == nil,
        let relation = register.relations.containers.first,
        let identifier = self.relation(relation) else {
      return nil
    }
    return self.register(identifier)
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ state: borrowing NativeRegisterState,
                              register: RegisterRecord,
                              model: RegisterDescription)
      throws(GDBHandlerError) {
    let count = register.bytes
    let start = output.count
    guard output.freeCapacity >= count else {
      throw .capacity
    }
    do {
      try state.read(register, container: model.container(register),
                     into: &output)
    } catch {
      throw .debuggee(error)
    }
    guard output.count - start == count, output.freeCapacity >= count else {
      throw .capacity
    }
    for _ in 0 ..< count {
      output.append(0)
    }
    for index in (0 ..< count).reversed() {
      let byte = output[start + index]
      output[start + index * 2] = (byte >> 4).hexadecimal
      output[start + index * 2 + 1] = byte.hexadecimal
    }
  }
}
