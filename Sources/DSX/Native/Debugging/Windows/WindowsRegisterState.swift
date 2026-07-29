// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(arm64) || arch(i386) || arch(x86_64))
internal import WinSDK

internal struct WindowsRegisterState: ~Copyable {
  private let thread: DWORD
  private let handle: WindowsHandle
#if arch(i386) || arch(x86_64)
  private let state: WindowsXState
#else
  private var context: CONTEXT
#endif

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try identifier.thread.native
    let access = THREAD_GET_CONTEXT | THREAD_SET_CONTEXT
    guard let native = OpenThread(access, false, thread) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
    let handle = WindowsHandle(native)
#if arch(i386) || arch(x86_64)
    let state = try WindowsXState(handle.value)
    self.state = consume state
#else
    let context = try CONTEXT(handle.value, flags: CONTEXT_ALL)
    self.context = context
#endif
    self.thread = thread
    self.handle = consume handle
  }
}

extension WindowsRegisterState {
#if arch(i386) || arch(x86_64)
  private func location(_ register: RegisterIdentifier)
      throws(Debuggee.Error) -> (UnsafeMutablePointer<UInt8>, Int, Int) {
    if let index = register.ymm {
      guard let vector = state.vector else {
        throw .register
      }
      let address = UnsafeMutableRawPointer(vector + index)
      return (address.assumingMemoryBound(to: UInt8.self), 16, 16)
    }
    let layout = try WindowsRegisterState.layout(register)
    let address = UnsafeMutableRawPointer(state.context) + layout.offset
    return (address.assumingMemoryBound(to: UInt8.self), layout.native,
            layout.size)
  }
#endif

  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
#if arch(i386) || arch(x86_64)
    let (address, native, size) = try location(register)
    guard output.freeCapacity >= size else {
      throw .register
    }
    for index in 0 ..< native {
      output.append(address[index])
    }
    for _ in native ..< size {
      output.append(0)
    }
#else
    let layout = try WindowsRegisterState.layout(register)
    try output.extend(context, offset: layout.offset, native: layout.native,
                      size: layout.size)
#endif
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
#if arch(i386) || arch(x86_64)
    let (address, native, size) = try location(register)
    guard bytes.count == size else {
      throw .register
    }
    for index in 0 ..< native {
      address[index] = bytes[index]
    }
#else
    let layout = try WindowsRegisterState.layout(register)
    try bytes.narrow(offset: layout.offset, native: layout.native,
                     size: layout.size, to: &context)
#endif
  }

  internal consuming func commit(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    guard try thread == identifier.thread.native else {
      throw .thread
    }
#if arch(i386) || arch(x86_64)
    guard SetThreadContext(handle.value, state.context) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
#else
    try context.commit(to: handle.value)
#endif
  }
}

#endif
