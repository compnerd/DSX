// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(arm64) || arch(i386) || arch(x86_64))
internal import WinSDK

internal struct WindowsRegisterState: ~Copyable {
  private let thread: DWORD
  private let handle: WindowsHandle
  private var context: CONTEXT

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try identifier.thread.native
    let access = THREAD_GET_CONTEXT | THREAD_SET_CONTEXT
    guard let native = OpenThread(access, false, thread) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
    let handle = WindowsHandle(native)
    let context = try CONTEXT(handle.value, flags: CONTEXT_ALL)
    self.thread = thread
    self.handle = consume handle
    self.context = context
  }
}

extension WindowsRegisterState {
  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let layout = try WindowsRegisterState.layout(register)
    try output.extend(context, offset: layout.offset, native: layout.native,
                      size: layout.size)
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    let layout = try WindowsRegisterState.layout(register)
    try bytes.narrow(offset: layout.offset, native: layout.native,
                     size: layout.size, to: &context)
  }

  internal consuming func commit(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    guard try thread == identifier.thread.native else {
      throw .thread
    }
    try context.commit(to: handle.value)
  }
}

#endif
