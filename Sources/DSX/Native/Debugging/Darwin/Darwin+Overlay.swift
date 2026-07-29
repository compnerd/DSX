// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

/// ClangImporter does not expose Darwin.ptrace.
internal func ptrace(_ request: CInt, _ process: pid_t,
                     _ address: UnsafeMutablePointer<CChar>?,
                     _ data: CInt) -> CInt {
  dsx_ptrace(request, process, address, data)
}

internal func ptrace(_ process: pid_t, denied: inout CInt) -> CInt {
  dsx_ptrace_attach(process, &denied)
}

/// ClangImporter does not expose Darwin's PT_* macros from <sys/ptrace.h>.
internal let kPTContinue: CInt = 7
internal let kPTKill: CInt = 8
internal let kPTStep: CInt = 9
internal let kPTAttach: CInt = 10
internal let kPTDetach: CInt = 11
internal let kPTThreadUpdate: CInt = 13
internal let kPTAttachException: CInt = 14

/// Darwin's private spawn flag used by debugserver and LLDB to disable ASLR.
///
/// The SDK does not publish this macro through `<spawn.h>`. Keep the fallback
/// at the libc boundary, matching `_POSIX_SPAWN_DISABLE_ASLR` in Darwin's
/// `posix_spawn` implementation.
internal let kPOSIXSpawnDisableASLR: CShort = 0x0100

internal let kVMMemoryMalloc = UInt32(VM_MEMORY_MALLOC)
internal let kVMMemoryMallocSmall = UInt32(VM_MEMORY_MALLOC_SMALL)
internal let kVMMemoryMallocLarge = UInt32(VM_MEMORY_MALLOC_LARGE)
internal let kVMMemoryMallocHuge = UInt32(VM_MEMORY_MALLOC_HUGE)
internal let kVMMemoryStack = UInt32(VM_MEMORY_STACK)
internal let kVMMemoryMallocTiny = UInt32(VM_MEMORY_MALLOC_TINY)
internal let kVMMemoryMallocLargeReusable =
    UInt32(VM_MEMORY_MALLOC_LARGE_REUSABLE)
internal let kVMMemoryMallocLargeReused = UInt32(VM_MEMORY_MALLOC_LARGE_REUSED)
internal let kVMMemoryMallocNano = UInt32(VM_MEMORY_MALLOC_NANO)
internal let kVMMemoryRealloc = UInt32(VM_MEMORY_REALLOC)
internal let kVMMemorySBRK = UInt32(VM_MEMORY_SBRK)
internal let kVMMemorySanitizer = UInt32(VM_MEMORY_SANITIZER)
internal let kSMEmpty = UInt8(SM_EMPTY)
internal let kCPUSubtypeMask: UInt32 = 0xff00_0000

/// ClangImporter does not expose Darwin's pointer-valued RTLD_DEFAULT macro.
@_transparent
internal var kRTLDDefault: UnsafeMutableRawPointer? {
  UnsafeMutableRawPointer(bitPattern: -2)
}

#if arch(arm64)
/// ESR_EL1 exception classes for hardware debug traps.
internal let kARMExceptionBreakpointLower: UInt64 = 0x30
internal let kARMExceptionBreakpointCurrent: UInt64 = 0x31
internal let kARMExceptionStepLower: UInt64 = 0x32
internal let kARMExceptionStepCurrent: UInt64 = 0x33
internal let kARMExceptionSoftwareBreakpoint: UInt64 = 0x3c
internal let kARMExceptionInstructionAbortLower: UInt64 = 0x20
internal let kARMExceptionInstructionAbortCurrent: UInt64 = 0x21
internal let kARMExceptionDataAbortLower: UInt64 = 0x24
internal let kARMExceptionDataAbortCurrent: UInt64 = 0x25
internal let kARMExceptionWatchpointLower: UInt64 = 0x34
internal let kARMExceptionWatchpointCurrent: UInt64 = 0x35
internal let kARMWatchpointNumberValid: UInt32 = 1 << 17
internal let kARMWatchpointNumberShift: UInt32 = 18
internal let kARMWatchpointNumberMask: UInt32 = 0x3f
/// MDSCR_EL1.SS arms architectural single stepping on Darwin.
internal let kARMDebugSingleStep: UInt64 = 1
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
