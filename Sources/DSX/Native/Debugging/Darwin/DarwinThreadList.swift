// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinThreadList: ~Copyable {
  private let storage: thread_act_array_t
  private var suspended = 0
  internal let count: Int

  @inline(never)
  internal init(_ process: ProcessIdentifier,
                control: borrowing DarwinDebugControl = DarwinDebugControl())
      throws(Debuggee.Error) {
    let task = try control.task(process)
    var storage: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    let status = task_threads(task.handle, &storage, &count)
    guard status == KERN_SUCCESS, let storage else {
      throw Debuggee.Error(mach: status, invalid: .thread)
    }
    self.storage = storage
    self.count = Int(count)
  }

  @inline(never)
  deinit {
    for index in 0 ..< count {
      let thread = storage[index]
      if thread == MACH_PORT_NULL {
        continue
      }
      if index < suspended {
        _ = thread_resume(thread)
      }
      _ = mach_port_deallocate(mach_task_self_, thread)
    }
    let address = vm_address_t(UInt(bitPattern: storage))
    let size = vm_size_t(count) * vm_size_t(MemoryLayout<thread_t>.stride)
    _ = vm_deallocate(mach_task_self_, address, size)
  }

  internal subscript(_ index: Int) -> thread_act_t {
    storage[index]
  }

  // The snapshot owns these holds, independently of task suspensions and
  // per-thread holds acquired by the application or another controller.
  internal mutating func suspend() throws(Debuggee.Error) {
    while suspended < count {
      let thread = storage[suspended]
      if thread > MACH_PORT_NULL {
        let status = thread_suspend(thread)
        guard status == KERN_SUCCESS else {
          throw Debuggee.Error(mach: status, invalid: .thread)
        }
      }
      suspended += 1
    }
  }

  internal mutating func resume() throws(Debuggee.Error) {
    while suspended > 0 {
      let thread = storage[suspended - 1]
      if thread > MACH_PORT_NULL {
        let status = thread_resume(thread)
        guard status == KERN_SUCCESS else {
          throw Debuggee.Error(mach: status, invalid: .thread)
        }
      }
      suspended -= 1
    }
  }

  @inline(__always)
  internal mutating func take(_ identifier: ThreadIdentifier)
      throws(Debuggee.Error) -> thread_act_t {
    guard suspended == 0 else {
      throw .state
    }
    for index in 0 ..< count {
      let thread = storage[index]
      guard try ThreadIdentifier(mach: thread) == identifier else {
        continue
      }
      storage[index] = 0
      return thread
    }
    throw .thread
  }
}
#endif
