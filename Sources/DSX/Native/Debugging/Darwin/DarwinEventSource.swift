// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal struct DarwinEventSource: ~Copyable {
  internal var polling: Bool { false }

  internal init() {
  }

  internal init(_ mode: DSX.Events) throws(Debuggee.Error) {
    if case .descriptor = mode {
      throw .unsupported
    }
  }

  internal func configure(_ control: inout DarwinDebugControl) {
  }

  internal func drain() throws(Debuggee.Error) {
  }

  internal func wait<Failure: Error>(_ control: borrowing DarwinDebugControl,
                                     _ body: EventWait<Failure>) throws(Failure)
      -> WaitResult {
    let exceptions = control.exceptions
    let handles: InlineArray<2, WaitHandle> =
        [WaitHandle(exceptions?.descriptor ?? -1),
         WaitHandle(control.reader ?? -1)]
    let timeout: Duration? = switch exceptions?.exited {
    case true?: .zero
    case false?: nil
    case nil: Tuning.Debuggee.polling
    }
    return try body(timeout, handles.span)
  }
}
#endif
