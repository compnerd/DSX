// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal final class DarwinTask: Sendable {
  internal let handle: mach_port_name_t

  @inline(never)
  internal init(_ process: ProcessIdentifier, retries: Int = 0,
                delay: useconds_t = 0) throws(Debuggee.Error) {
    let identifier = try process.native
    var handle: mach_port_name_t = 0
    var status: kern_return_t = KERN_FAILURE
    for attempt in 0 ... retries {
      status = task_for_pid(mach_task_self_, identifier, &handle)
      if status == KERN_SUCCESS {
        self.handle = handle
        return
      }
      if attempt < retries {
        _ = usleep(delay)
      }
    }
    throw Debuggee.Error(task: status, invalid: .process)
  }

  deinit {
    _ = mach_port_deallocate(mach_task_self_, handle)
  }

  internal var suspension: integer_t {
    get throws(Debuggee.Error) {
      var basic = task_basic_info_data_t()
      let bytes = MemoryLayout.size(ofValue: basic)
      let capacity = bytes / MemoryLayout<integer_t>.size
      var count = mach_msg_type_number_t(capacity)
      let status = withUnsafeMutablePointer(to: &basic) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
          task_info(handle, task_flavor_t(TASK_BASIC_INFO), $0, &count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw Debuggee.Error(mach: status, invalid: .process)
      }
      return basic.suspend_count
    }
  }

  // XNU publishes SSTOP before acquiring the corresponding task hold.
  // SIGCONT must not race that acquisition, or the process can remain held.
  internal func settle(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    let deadline = try Deadline(seconds: 2, now: Host.time)
    repeat {
      if try process.stopped, try suspension > 0 {
        return
      }
      usleep(1_000)
    } while try deadline.remaining(at: Host.time) > 0
    throw .system(ETIMEDOUT)
  }
}

extension Debuggee.Error {
  internal init(task code: kern_return_t, invalid: Debuggee.Error) {
    self = code == KERN_FAILURE ? .access
                                : Debuggee.Error(mach: code, invalid: invalid)
  }

  internal init(virtual code: kern_return_t) {
    self = code == KERN_INVALID_ADDRESS
                ? .memory
                : Debuggee.Error(mach: code, invalid: .memory)
  }
}

extension Debuggee.Error {
  internal init(mach code: kern_return_t, invalid: Debuggee.Error) {
    self = switch code {
    case KERN_INVALID_ARGUMENT: invalid
    case KERN_PROTECTION_FAILURE, KERN_NO_ACCESS: .access
    case KERN_NOT_SUPPORTED: .unsupported
    default: .system(CInt(code))
    }
  }
}
#endif
