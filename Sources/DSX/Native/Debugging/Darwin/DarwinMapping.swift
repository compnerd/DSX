// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinMapping {
  internal let address: mach_vm_address_t
  internal let size: mach_vm_size_t
  internal let protection: vm_prot_t
  fileprivate let tag: UInt32
  fileprivate let sharing: UInt8
}

extension DarwinMapping {
  internal var kind: Debuggee.MemoryRegion.Kind? {
    switch tag {
    case VM_MEMORY_STACK: .stack(protection == VM_PROT_NONE)
    case VM_MEMORY_MALLOC:
      if protection == VM_PROT_NONE {
        .malloc(.guarded)
      } else {
        sharing == SM_EMPTY ? .malloc(.reserved) : .malloc(.metadata)
      }
    case VM_MEMORY_MALLOC_TINY: .heap(.tiny)
    case VM_MEMORY_MALLOC_SMALL: .heap(.small)
    case VM_MEMORY_MALLOC_LARGE: .heap(.large)
    case VM_MEMORY_MALLOC_NANO, VM_MEMORY_MALLOC_LARGE_REUSED,
        VM_MEMORY_MALLOC_LARGE_REUSABLE, VM_MEMORY_MALLOC_HUGE,
        VM_MEMORY_REALLOC, VM_MEMORY_SBRK, VM_MEMORY_SANITIZER: .heap(.unknown)
    default: nil
    }
  }
}

extension DarwinTask {
  internal func mapping(at requested: UInt64, depth: inout natural_t,
                        invalid: Debuggee.Error = .memory)
      throws(Debuggee.Error) -> DarwinMapping? {
    var address = mach_vm_address_t(requested)
    while true {
      var size: mach_vm_size_t = 0
      var info = vm_region_submap_info_64()
      let bytes = MemoryLayout<vm_region_submap_info_64>.size
      let words = bytes / MemoryLayout<integer_t>.size
      var count = mach_msg_type_number_t(words)
      let status = withUnsafeMutablePointer(to: &info) { info in
        info.withMemoryRebound(to: integer_t.self, capacity: words) { info in
          mach_vm_region_recurse(handle, &address, &size, &depth, info, &count)
        }
      }
      if status == KERN_INVALID_ADDRESS {
        return nil
      }
      guard status == KERN_SUCCESS else {
        throw Debuggee.Error(mach: status, invalid: invalid)
      }
      guard info.is_submap > 0 else {
        return DarwinMapping(address: address, size: size,
                             protection: info.protection, tag: info.user_tag,
                             sharing: info.share_mode)
      }
      depth += 1
      address = mach_vm_address_t(requested)
    }
  }
}
#endif
