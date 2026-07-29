// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinThreadList: ~Copyable {
  private let storage: thread_act_array_t
  internal let count: Int

  @inline(__always)
  internal init(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    let task = try DarwinTask(process)
    var storage: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    let status = task_threads(task.handle, &storage, &count)
    guard status == KERN_SUCCESS, let storage else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    self.storage = storage
    self.count = Int(count)
  }

  @inline(__always)
  deinit {
    for index in 0 ..< count {
      let thread = storage[index]
      if thread == MACH_PORT_NULL {
        continue
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

  @inline(__always)
  internal mutating func take(_ identifier: ThreadIdentifier)
      throws(Debuggee.Error) -> thread_act_t {
    for index in 0 ..< count {
      let thread = storage[index]
      guard try identity(thread) == identifier else {
        continue
      }
      storage[index] = 0
      return thread
    }
    throw .thread
  }
}
#endif
