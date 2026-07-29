// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

@_transparent
internal var PROC_PIDARCHINFO: CInt { 19 }

internal func ptrace(_ request: CInt, _ process: pid_t,
                     _ address: UnsafeMutablePointer<CChar>?,
                     _ data: CInt) -> CInt {
  dsx_ptrace(request, process, address, data)
}

internal func ptrace(_ process: pid_t, denied: inout CInt) -> CInt {
  dsx_ptrace_attach(process, &denied)
}

@_transparent
internal var PT_CONTINUE: CInt { 7 }

@_transparent
internal var PT_KILL: CInt { 8 }

@_transparent
internal var PT_STEP: CInt { 9 }

@_transparent
internal var PT_ATTACH: CInt { 10 }

@_transparent
internal var PT_DETACH: CInt { 11 }

@_transparent
internal var PT_THUPDATE: CInt { 13 }

@_transparent
internal var PT_ATTACHEXC: CInt { 14 }

@_transparent
internal var _POSIX_SPAWN_DISABLE_ASLR: CShort { 0x0100 }

@_transparent
internal var VM_MEMORY_MALLOC: UInt32 { UInt32(Darwin.VM_MEMORY_MALLOC) }

@_transparent
internal var VM_MEMORY_MALLOC_SMALL: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_SMALL)
}

@_transparent
internal var VM_MEMORY_MALLOC_LARGE: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_LARGE)
}

@_transparent
internal var VM_MEMORY_MALLOC_HUGE: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_HUGE)
}

@_transparent
internal var VM_MEMORY_STACK: UInt32 { UInt32(Darwin.VM_MEMORY_STACK) }

@_transparent
internal var VM_MEMORY_MALLOC_TINY: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_TINY)
}

@_transparent
internal var VM_MEMORY_MALLOC_LARGE_REUSABLE: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_LARGE_REUSABLE)
}

@_transparent
internal var VM_MEMORY_MALLOC_LARGE_REUSED: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_LARGE_REUSED)
}

@_transparent
internal var VM_MEMORY_MALLOC_NANO: UInt32 {
  UInt32(Darwin.VM_MEMORY_MALLOC_NANO)
}

@_transparent
internal var VM_MEMORY_REALLOC: UInt32 { UInt32(Darwin.VM_MEMORY_REALLOC) }

@_transparent
internal var VM_MEMORY_SBRK: UInt32 { UInt32(Darwin.VM_MEMORY_SBRK) }

@_transparent
internal var VM_MEMORY_SANITIZER: UInt32 { UInt32(Darwin.VM_MEMORY_SANITIZER) }

@_transparent
internal var SM_EMPTY: UInt8 { UInt8(Darwin.SM_EMPTY) }

@_transparent
internal var RTLD_DEFAULT: UnsafeMutableRawPointer? {
  UnsafeMutableRawPointer(bitPattern: -2)
}

#if arch(arm64)
@_transparent
internal var ESR_EC_BKPT_REG_MATCH_EL0: UInt64 { 0x30 }

@_transparent
internal var ESR_EC_BKPT_REG_MATCH_EL1: UInt64 { 0x31 }

@_transparent
internal var ESR_EC_SW_STEP_DEBUG_EL0: UInt64 { 0x32 }

@_transparent
internal var ESR_EC_SW_STEP_DEBUG_EL1: UInt64 { 0x33 }

@_transparent
internal var ESR_EC_BRK_AARCH64: UInt64 { 0x3c }

@_transparent
internal var ESR_EC_IABORT_EL0: UInt64 { 0x20 }

@_transparent
internal var ESR_EC_IABORT_EL1: UInt64 { 0x21 }

@_transparent
internal var ESR_EC_DABORT_EL0: UInt64 { 0x24 }

@_transparent
internal var ESR_EC_DABORT_EL1: UInt64 { 0x25 }

@_transparent
internal var ESR_EC_WATCHPT_MATCH_EL0: UInt64 { 0x34 }

@_transparent
internal var ESR_EC_WATCHPT_MATCH_EL1: UInt64 { 0x35 }

@_transparent
internal var MDSCR_SS: UInt64 { 1 }
#endif

@_transparent
internal var POSIX_SPAWN_START_SUSPENDED: CShort {
  CShort(Darwin.POSIX_SPAWN_START_SUSPENDED)
}

@_transparent
internal var POSIX_SPAWN_SETPGROUP: CShort {
  CShort(Darwin.POSIX_SPAWN_SETPGROUP)
}

@_transparent
internal var POSIX_SPAWN_SETSIGDEF: CShort {
  CShort(Darwin.POSIX_SPAWN_SETSIGDEF)
}

@_transparent
internal var POSIX_SPAWN_SETSIGMASK: CShort {
  CShort(Darwin.POSIX_SPAWN_SETSIGMASK)
}

@_transparent
internal var POSIX_SPAWN_CLOEXEC_DEFAULT: CShort {
  CShort(Darwin.POSIX_SPAWN_CLOEXEC_DEFAULT)
}
#endif
