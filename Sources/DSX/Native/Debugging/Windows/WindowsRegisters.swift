// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(arm64) || arch(i386) || arch(x86_64))
internal import WinSDK

internal struct WindowsRegisterState: ~Copyable {
  fileprivate let thread: DWORD
  fileprivate let handle: WindowsHandle
  fileprivate var context: CONTEXT

  fileprivate init(thread: DWORD, handle: consuming WindowsHandle,
                   context: CONTEXT) {
    self.thread = thread
    self.handle = consume handle
    self.context = context
  }
}

internal enum WindowsRegisters {
  internal typealias State = WindowsRegisterState

  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal static func snapshot(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> WindowsRegisterState {
    try capture(identifier.thread.native)
  }

  internal static func read(_ state: borrowing WindowsRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let layout = try layout(register)
    try RegisterBytes.extend(state.context, offset: layout.offset,
                             native: layout.native, size: layout.size,
                             into: &output)
  }

  internal static func write(_ state: inout WindowsRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    let layout = try layout(register)
    try RegisterBytes.narrow(bytes, offset: layout.offset,
                             native: layout.native, size: layout.size,
                             to: &state.context)
  }

  internal static func commit(_ state: consuming WindowsRegisterState,
                              thread identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    let state = consume state
    let thread = try identifier.thread.native
    guard state.thread == thread else {
      throw .thread
    }
    try WindowsContext.commit(state.context, to: state.handle.value)
  }
}

private func capture(_ thread: DWORD) throws(Debuggee.Error)
    -> WindowsRegisterState {
  let access = THREAD_GET_CONTEXT | THREAD_SET_CONTEXT
  guard let native = OpenThread(access, false, thread) else {
    throw WindowsError.debuggee(GetLastError(), invalid: .thread)
  }
  let owner = WindowsHandle(native)
  let context = try WindowsContext.snapshot(owner.value, flags: CONTEXT_ALL)
  return WindowsRegisterState(thread: thread, handle: consume owner,
                              context: context)
}
#endif
