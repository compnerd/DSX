// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinContinuationPlan {
  internal let request: CInt
  internal let signal: CInt
  internal let interrupt: Bool

  internal init(_ actions: borrowing Debuggee.Continuations,
                process: ProcessIdentifier, threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    var stepping = false
    var signal: CInt?
    for index in 0 ..< threads.count {
      let thread = try identity(threads[index])
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      guard let action = actions.action(identifier) else {
        continue
      }
      if let delivered = action.signal {
        guard signal == nil || signal == delivered else {
          throw .state
        }
        signal = delivered
      }
      if action.operation == .step {
        stepping = true
      }
    }
    let action = actions.action(process)
#if arch(arm64)
    request = PT_CONTINUE
#elseif arch(x86_64)
    request = stepping || action?.operation == .step ? PT_STEP : PT_CONTINUE
#else
#error("Implement Darwin continuation requests for this architecture")
#endif
    if stepping {
      self.signal = signal ?? 0
      interrupt = false
    } else {
      switch action?.operation {
      case .stop:
        self.signal = 0
        interrupt = true
      case .resume, nil:
        self.signal = signal ?? action?.signal ?? 0
        interrupt = false
      case .step:
        self.signal = action?.signal ?? 0
        interrupt = false
      }
    }
  }
}
#endif
