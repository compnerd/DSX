// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      let owner = try identifier(self)
#if os(FreeBSD)
      let count = ptrace(PT_GETNUMLWPS, owner, nil, 0)
      guard count >= 0 else {
        throw UnixError.debuggee(errno, invalid: .process, support: true)
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
          throw UnixError.debuggee(errno, invalid: .process, support: true)
        }
        var threads = Array<ProcessThreadIdentifier>()
        threads.reserveCapacity(Int(result))
        for index in 0 ..< Int(result) {
          let identifier = ids[index]
          if identifier > 0 {
            threads.append(pair(self, thread: identifier))
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
          throw UnixError.debuggee(errno, invalid: .process, support: true)
        }
        guard state.pts_tid > 0 else {
          return threads
        }
        threads.append(pair(self, thread: state.pts_tid))
        request = PT_GET_THREAD_NEXT
      }
#endif
    }
  }
}

extension ProcessThreadIdentifier {
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

private func pair(_ process: ProcessIdentifier, thread: pid_t)
    -> ProcessThreadIdentifier {
  let thread = ThreadIdentifier(rawValue: UInt64(thread))
  ProcessThreadIdentifier(process: process, thread: thread)
}

private func identifier(_ process: ProcessIdentifier) throws(Debuggee.Error)
    -> pid_t {
  guard process.rawValue <= UInt64(pid_t.max) else {
    throw .process
  }
  return pid_t(process.rawValue)
}

#endif
