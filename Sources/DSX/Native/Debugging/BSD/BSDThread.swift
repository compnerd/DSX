// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      let owner = try native
#if os(FreeBSD)
      let count = ptrace(PT_GETNUMLWPS, owner, nil, 0)
      guard count >= 0 else {
        throw Debuggee.Error(unix: errno, invalid: .process, support: true)
      }
      guard count > 0 else {
        return Array<ProcessThreadIdentifier>()
      }
      let capacity = Int(count)
      return try withUnsafeTemporaryAllocation(of: pid_t.self,
                                               capacity: capacity,
                                               { ids throws(Debuggee.Error) in
        guard let address = ids.baseAddress else {
          throw .state
        }
        let result = ptrace(PT_GETLWPLIST, owner,
                            UnsafeMutableRawPointer(address)
                              .assumingMemoryBound(to: CChar.self),
                            CInt(ids.count))
        guard result >= 0, result <= count else {
          throw Debuggee.Error(unix: errno, invalid: .process, support: true)
        }
        var threads = Array<ProcessThreadIdentifier>()
        threads.reserveCapacity(Int(result))
        for index in 0 ..< Int(result) {
          let identifier = ids[index]
          if identifier > 0 {
            threads.append(ProcessThreadIdentifier(identifier, process: self))
          }
        }
        return threads
      })
#else
      var state = ptrace_thread_state()
      var request = PT_GET_THREAD_FIRST
      var threads = Array<ProcessThreadIdentifier>()
      while true {
        let result = withUnsafeMutablePointer(to: &state) { state in
          let pointer = UnsafeMutableRawPointer(state)
            .assumingMemoryBound(to: CChar.self)
          ptrace(request, owner, pointer,
                 CInt(MemoryLayout<ptrace_thread_state>.size))
        }
        guard result == 0 else {
          throw Debuggee.Error(unix: errno, invalid: .process, support: true)
        }
        guard state.pts_tid > 0 else {
          return threads
        }
        threads.append(ProcessThreadIdentifier(state.pts_tid, process: self))
        request = PT_GET_THREAD_NEXT
      }
#endif
    }
  }
}

extension ProcessThreadIdentifier {
  internal init(_ thread: pid_t, process: ProcessIdentifier) {
    self.init(process: process,
              thread: ThreadIdentifier(rawValue: UInt64(thread)))
  }

  internal var alive: Bool {
    get throws(Debuggee.Error) {
      do {
        return try process.threads.contains(self)
      } catch Debuggee.Error.process {
        return false
      } catch {
        throw error
      }
    }
  }

  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      guard try alive else {
        throw .thread
      }
      return Debuggee.Thread.Info(thread: self)
    }
  }
}

#endif
