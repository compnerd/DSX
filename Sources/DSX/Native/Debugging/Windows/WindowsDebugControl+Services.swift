// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  // MARK: - Session Services

  internal mutating func output(_ process: ProcessIdentifier,
                                into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let count = try forward(process, current: self.process,
                            pending: &self.output, into: &output)
    DSX.log("forwarding \(count) bytes of debuggee output", level: .trace,
            channel: .process)
  }

  internal func input(_ process: ProcessIdentifier,
                      bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    guard self.process == process, let writer else {
      throw .state
    }
    try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      var offset = 0
      while offset < bytes.count {
        var count: DWORD = 0
        let requested = DWORD(clamping: bytes.count - offset)
        let base = bytes.baseAddress!.advanced(by: offset)
        guard WriteFile(writer, base, requested, &count, nil), count > 0 else {
          throw WindowsDebugControl.failure(GetLastError())
        }
        offset += Int(count)
      }
    }
  }

  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
  }

  internal mutating func complete(_ event: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
  }

  internal mutating func collect() -> Debuggee.Event? {
    nil
  }

  internal func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    guard calls == nil else {
      throw .unsupported
    }
  }
}
#endif
