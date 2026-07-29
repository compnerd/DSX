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
      throw DarwinError.task(status, invalid: .process)
    }
    self.handle = handle
  }

  @inline(never)
  internal static func attach(_ process: ProcessIdentifier, retries: Int,
                              delay: useconds_t) throws(Debuggee.Error)
      -> DarwinTask {
    let identifier = try process.native
    var handle: mach_port_name_t = 0
    var status: kern_return_t = KERN_FAILURE
    for attempt in 0 ... retries {
      status = task_for_pid(mach_task_self_, identifier, &handle)
      if status == KERN_SUCCESS {
        return DarwinTask(handle: handle)
      }
      if attempt < retries {
        _ = usleep(delay)
      }
    }
    throw DarwinError.task(status, invalid: .process)
  }

  private init(handle: mach_port_name_t) {
    self.handle = handle
  }

  deinit {
    _ = mach_port_deallocate(mach_task_self_, handle)
  }
}

internal enum DarwinError {
  internal static func task(_ code: kern_return_t,
                            invalid: Debuggee.Error) -> Debuggee.Error {
    if code == KERN_FAILURE {
      .access
    } else {
      debuggee(code, invalid: invalid)
    }
  }

  internal static func memory(_ code: kern_return_t) -> Debuggee.Error {
    if code == KERN_INVALID_ADDRESS {
      .memory
    } else {
      debuggee(code, invalid: .memory)
    }
  }

  internal static func debuggee(_ code: kern_return_t,
                                invalid: Debuggee.Error) -> Debuggee.Error {
    switch code {
    case KERN_INVALID_ARGUMENT: invalid
    case KERN_PROTECTION_FAILURE, KERN_NO_ACCESS: .access
    case KERN_NOT_SUPPORTED: .unsupported
    default: .system(CInt(code))
    }
  }
}
#endif
