// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinTask: ~Copyable, Sendable {
  internal let handle: mach_port_name_t

  internal init(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    let identifier = try process.native
    var handle: mach_port_name_t = 0
    let status = task_for_pid(mach_task_self_, identifier, &handle)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(task: status, invalid: .process)
    }
    self.handle = handle
  }

  @inline(never)
  internal init(_ process: ProcessIdentifier, retries: Int, delay: useconds_t)
      throws(Debuggee.Error) {
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
}

extension Debuggee.Error {
  internal init(task code: kern_return_t, invalid: Debuggee.Error) {
    self = if code == KERN_FAILURE {
      .access
    } else {
      Debuggee.Error(mach: code, invalid: invalid)
    }
  }

  internal init(virtual code: kern_return_t) {
    self = if code == KERN_INVALID_ADDRESS {
      .memory
    } else {
      Debuggee.Error(mach: code, invalid: .memory)
    }
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
