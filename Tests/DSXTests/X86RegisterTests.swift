// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if arch(i386) || arch(x86_64)
#if os(Windows)
internal import WinSDK
#endif

@Suite
internal struct X86RegisterTests {
  @Test
  internal func layout() throws {
#if os(Windows)
    let configurations = [RegisterConfiguration()]
#else
    let configurations = [false, true].map { RegisterConfiguration(vector: $0) }
#endif
    for configuration in configurations {
      try layout(configuration)
    }
  }

  private func layout(_ configuration: RegisterConfiguration) throws {
    let description = RegisterDescription(configuration)
    let available = configuration.vector
    let count = RegisterConfiguration.vectors
#if arch(i386)
    let legacy = 41
#elseif os(Linux) || os(Android)
    let legacy = 59
#elseif os(anyAppleOS)
    let legacy = 60
#else
    let legacy = 57
#endif
    #expect(description.count == legacy + (available ? count : 0))
    #expect(description.contains(RegisterFeatureIdentifier(rawValue: 3))
            == available)
    var offset = 0
    for index in 0 ..< description.count {
      let register = try #require(description.register(index))
      #expect(register.numbers.gdb == index)
      #expect(register.numbers.lldb == index)
      #expect(register.offset == offset)
      offset += register.bytes
    }
    #expect(description.size(.gdb) == offset)
    #expect(description.register(description.count) == nil)
  }

#if os(Windows)
  @Test
  internal func vectors() throws {
    let launch = Debuggee.Launch(executable: CommandLine.arguments[0],
                                 output: "NUL", error: "NUL")
    var session = DebugSession(launch: launch)
    _ = try session.spawn()
    defer { try? session.close(cause: .failure) }
    try session.settle()
    let threads = session.debuggee.processes.first?.threads
    let thread = try #require(threads?.first?.identifier)
#if arch(i386)
    let first = I386Register.xmm0.rawValue
    let flags = DSX::CONTEXT_EXTENDED_REGISTERS
    #expect(DSX::CONTEXT_ALL & flags == flags)
#else
    let first = X86_64Register.xmm0.rawValue
#endif
    var registers = try NativeRegisterState(thread)
    let original = try bytes(registers, register: first)
    let value = Array<UInt8>(1 ... 16)
    try registers.write(RegisterIdentifier(rawValue: first), bytes: value.span)
    try registers.commit(thread)
    var updated = try NativeRegisterState(thread)
    #expect(try bytes(updated, register: first) == value)
    try updated.write(RegisterIdentifier(rawValue: first), bytes: original.span)
    try updated.commit(thread)
    let restored = try NativeRegisterState(thread)
    #expect(try bytes(restored, register: first) == original)
  }

  @Test
  internal func preservation() throws {
    var identifier: DWORD = 0
    let handle = try #require(CreateThread(nil, 0, { _ in 0 }, nil,
                                           DWORD(WinSDK.CREATE_SUSPENDED),
                                           &identifier))
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, WinSDK.INFINITE)
      _ = CloseHandle(handle)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let selected = ThreadIdentifier(rawValue: UInt64(identifier))
    let thread = ProcessThreadIdentifier(process: process, thread: selected)
    let control = NativeDebugControl()
    let original = try SavedRegisters(thread, identifier: 1, control: control)
    defer {
      do {
        var registers = try NativeRegisterState(thread)
        try registers.restore(original)
        try registers.commit(thread)
      } catch {
        Issue.record(error)
      }
    }
    var registers = try NativeRegisterState(thread)
    guard registers.configuration.vector else {
      #expect(WinSDK.GetEnabledXStateFeatures() & DSX::XSTATE_MASK_AVX == 0)
      return
    }
#if arch(i386)
    let first = I386Register.ymm0h.rawValue
    let low = I386Register.xmm0.rawValue
#else
    let first = X86_64Register.ymm0h.rawValue
    let low = X86_64Register.xmm0.rawValue
#endif
    let count = UInt32(RegisterConfiguration.vectors)
    var lower = Array<Array<UInt8>>()
    for index in 0 ..< count {
      lower.append(try bytes(registers, register: low + index))
      let value = Array(repeating: UInt8(index + 1), count: 16)
      try registers.write(RegisterIdentifier(rawValue: first + index),
                          bytes: value.span)
    }
    try registers.commit(thread)
    let saved = try SavedRegisters(thread, identifier: 2, control: control)
    var updated = try NativeRegisterState(thread)
    for index in 0 ..< count {
      let expected = Array(repeating: UInt8(index + 1), count: 16)
      #expect(try bytes(updated, register: first + index) == expected)
      #expect(try bytes(updated, register: low + index) == lower[Int(index)])
      let value = Array(repeating: UInt8(index + 32), count: 16)
      try updated.write(RegisterIdentifier(rawValue: low + index),
                        bytes: value.span)
    }
    try updated.commit(thread)
    var restored = try NativeRegisterState(thread)
    for index in 0 ..< count {
      let expected = Array(repeating: UInt8(index + 1), count: 16)
      #expect(try bytes(restored, register: first + index) == expected)
      let value = Array(repeating: UInt8(index + 32), count: 16)
      #expect(try bytes(restored, register: low + index) == value)
    }
    try restored.restore(saved)
    try restored.commit(thread)
    let final = try NativeRegisterState(thread)
    for index in 0 ..< count {
      #expect(try bytes(final, register: low + index) == lower[Int(index)])
      let expected = Array(repeating: UInt8(index + 1), count: 16)
      #expect(try bytes(final, register: first + index) == expected)
    }
  }

  private func bytes(_ snapshot: borrowing NativeRegisterState,
                     register: UInt32) throws -> Array<UInt8> {
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: 16) { output throws(Debuggee.Error) in
      try snapshot.read(RegisterIdentifier(rawValue: register), into: &output)
    }
    return bytes
  }
#endif
}
#endif
