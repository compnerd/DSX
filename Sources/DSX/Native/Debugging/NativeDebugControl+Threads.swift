// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeDebugControl {
  internal func threads(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Array<ProcessThreadIdentifier> {
#if os(Android) || os(Linux)
    // PTRACE_EVENT_EXIT precedes disappearance from /proc. Keep native state
    // until waitpid reaps the exit, but never advertise an exiting thread as
    // available for register access or resumption.
    threads.compactMap { identifier, state in
      guard state.process == process, state.exiting == false,
          state.newborn == false else {
        return nil
      }
      let thread = ThreadIdentifier(rawValue: UInt64(identifier))
      return ProcessThreadIdentifier(process: process, thread: thread)
    }
#elseif os(anyAppleOS)
    try process.threads(control: self)
#elseif os(Windows)
    guard self.process == process else {
      throw .process
    }
    // Toolhelp can retain a thread after its exit event has been continued.
    // Debug events own this inventory; a snapshot must not resurrect it.
    return threads.keys.map { ProcessThreadIdentifier($0, process: process) }
#else
    try process.threads
#endif
  }
}
