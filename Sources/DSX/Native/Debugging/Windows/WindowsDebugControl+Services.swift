// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  // MARK: - Session Services

  @inline(never)
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
          throw Debuggee.Error(process: GetLastError())
        }
        offset += Int(count)
      }
    }
  }

  internal mutating func complete(_: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
    cursor = nil
    guard !breakpoints.isEmpty, let pending else {
      return
    }
    // Windows may expose a trapped context before delivering its debug event.
    // Publish that cause before a client removes or reuses the comparator.
    // DefaultIndices retains the dictionary and can force a copy on mutation.
    var next = threads.startIndex
    while next != threads.endIndex {
      let index = next
      threads.formIndex(after: &next)
      let thread = threads[index]
      guard thread.key != pending.dwThreadId, thread.value.reply == nil else {
        continue
      }
      if try thread.value.trapped {
        threads.values[index].execution = .trapped
        threads.values[index].reply = .deferred
      }
    }
    cursor = threads.startIndex
  }

  @inline(__always)
  internal mutating func collect() -> Debuggee.Event? {
    guard let process else {
      return nil
    }
    while let index = cursor, index != threads.endIndex {
      cursor = threads.index(after: index)
      guard threads[index].value.execution == .trapped else {
        continue
      }
      threads.values[index].execution = .stopped
      let identifier = ProcessThreadIdentifier(threads[index].key,
                                               process: process)
      return .stopped(Debuggee.Stop(thread: identifier, reason: .trace))
    }
    cursor = nil
    return nil
  }

  internal func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    guard calls == nil else {
      throw .unsupported
    }
  }
}
#endif
