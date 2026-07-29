// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

extension thread_act_t {
  internal func read<Value>(_ value: inout Value, flavor: Int32)
      throws(Debuggee.Error) {
    let words = MemoryLayout<Value>.size / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &value) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: words) {
        thread_get_state(self, thread_state_flavor_t(flavor), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .thread)
    }
  }

  internal func write<Value>(_ value: borrowing Value, flavor: Int32)
      throws(Debuggee.Error) {
    let words = MemoryLayout<Value>.size / MemoryLayout<natural_t>.size
    let count = mach_msg_type_number_t(words)
    let status = withUnsafePointer(to: value) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: words) {
        // Mach's input-only thread_state_t is imported as a mutable pointer.
        thread_set_state(self, thread_state_flavor_t(flavor),
                         UnsafeMutablePointer(mutating: $0), count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .thread)
    }
  }
}
#endif
