// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Windows) || os(FreeBSD) || os(OpenBSD)
internal struct PollingEventSource: ~Copyable {
  internal var polling: Bool { true }

  internal init() {
  }

  internal init(_ mode: DSX.Events) throws(Debuggee.Error) {
    if case .descriptor = mode {
      throw .unsupported
    }
  }

  internal func configure(_ control: inout NativeDebugControl) {
  }

  internal func drain() throws(Debuggee.Error) {
  }

  internal func wait<Failure: Error>(_ control: borrowing NativeDebugControl,
                                     _ body: EventWait<Failure>) throws(Failure)
      -> WaitResult {
    try body(NativeDebugControl.interval ?? Configuration.DebuggeePollInterval,
             Span())
  }
}
#endif
