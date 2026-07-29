// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

@_transparent
internal var AT_NULL: UInt64 {
#if os(Android)
  UInt64(Android.AT_NULL)
#else
  UInt64(Glibc.AT_NULL)
#endif
}

@_transparent
internal var AT_PHDR: UInt64 {
#if os(Android)
  UInt64(Android.AT_PHDR)
#else
  UInt64(Glibc.AT_PHDR)
#endif
}

@_transparent
internal var AT_PHENT: UInt64 {
#if os(Android)
  UInt64(Android.AT_PHENT)
#else
  UInt64(Glibc.AT_PHENT)
#endif
}

@_transparent
internal var AT_PHNUM: UInt64 {
#if os(Android)
  UInt64(Android.AT_PHNUM)
#else
  UInt64(Glibc.AT_PHNUM)
#endif
}

@_transparent
internal var PT_PHDR: UInt64 {
#if os(Android)
  UInt64(Android.PT_PHDR)
#else
  UInt64(Glibc.PT_PHDR)
#endif
}

@_transparent
internal var PT_DYNAMIC: UInt64 {
#if os(Android)
  UInt64(Android.PT_DYNAMIC)
#else
  UInt64(Glibc.PT_DYNAMIC)
#endif
}

@_transparent
internal var DT_NULL: UInt64 {
#if os(Android)
  UInt64(Android.DT_NULL)
#else
  UInt64(Glibc.DT_NULL)
#endif
}

@_transparent
internal var DT_DEBUG: UInt64 {
#if os(Android)
  UInt64(Android.DT_DEBUG)
#else
  UInt64(Glibc.DT_DEBUG)
#endif
}

#if arch(i386)
/// Offset of `u_debugreg` in Linux i386's `struct user`.
internal let kUserDebugRegisterOffset = 0xfc
/// Extended processor state note type from Linux UAPI `<asm/ptrace.h>`.
internal let NT_X86_XSTATE = 0x202
#elseif arch(x86_64)
/// Offset of `u_debugreg` in Linux x86-64's `struct user`.
internal let kUserDebugRegisterOffset = 0x350
#elseif arch(arm)
/// ELF note type from Linux UAPI `<asm/ptrace.h>`.
internal let NT_ARM_VFP = 0x400
#elseif arch(arm64)
/// ELF note types from Linux UAPI `<asm/ptrace.h>`.
internal let NT_ARM_TLS = 0x401
internal let NT_ARM_HW_BREAK = 0x402
internal let NT_ARM_HW_WATCH = 0x403
#endif

/// Linux's `ADDR_NO_RANDOMIZE` personality flag from `<sys/personality.h>`.
internal let kAddressNoRandomize: CUnsignedLong = 0x0004_0000

/// Query the current execution domain without changing it.
internal let kPersonalityQuery: CUnsignedLong = 0xffff_ffff

internal func ptrace(_ request: CInt, _ process: pid_t,
                     _ address: UnsafeMutableRawPointer?,
                     _ data: UnsafeMutableRawPointer?) -> CLong {
  dsx_ptrace(request, process, address, data)
}

@_transparent
internal func personality(_ persona: CUnsignedLong) -> CInt {
  dsx_personality(persona)
}

@_transparent
internal func grantpt(_ descriptor: CInt) -> CInt {
#if os(Android)
  Android.grantpt(descriptor)
#else
  dsx_grantpt(descriptor)
#endif
}

@_transparent
internal func unlockpt(_ descriptor: CInt) -> CInt {
#if os(Android)
  Android.unlockpt(descriptor)
#else
  dsx_unlockpt(descriptor)
#endif
}

internal func ptsname_r(_ descriptor: CInt, _ name: UnsafeMutablePointer<CChar>,
                        _ capacity: Int) -> CInt {
#if os(Android)
  Android.ptsname_r(descriptor, name, capacity)
#else
  dsx_ptsname_r(descriptor, name, capacity)
#endif
}

@_transparent
internal func tgkill(_ process: pid_t, _ thread: pid_t,
                     _ signal: CInt) -> CInt {
#if os(Android)
  Android.tgkill(process, thread, signal)
#else
  dsx_tgkill(process, thread, signal)
#endif
}

@_transparent
internal func open(_ path: UnsafePointer<CChar>, _ flags: CInt,
                   _ mode: mode_t) -> CInt {
  dsx_open(path, flags, mode)
}

#if os(Android)
@_transparent
internal func process_vm_readv(_ process: pid_t, _ local: UnsafePointer<iovec>,
                               _ locals: UInt, _ remote: UnsafePointer<iovec>,
                               _ remotes: UInt, _ flags: UInt) -> Int {
  Android.process_vm_readv(process, local, locals, remote, remotes, flags)
}

@_transparent
internal func process_vm_writev(_ process: pid_t, _ local: UnsafePointer<iovec>,
                                _ locals: UInt, _ remote: UnsafePointer<iovec>,
                                _ remotes: UInt, _ flags: UInt) -> Int {
  Android.process_vm_writev(process, local, locals, remote, remotes, flags)
}
#else
@_transparent
internal func process_vm_readv(_ process: pid_t, _ local: UnsafePointer<iovec>,
                               _ locals: UInt, _ remote: UnsafePointer<iovec>,
                               _ remotes: UInt, _ flags: UInt) -> Int {
  dsx_process_vm_readv(process, local, numericCast(locals), remote,
                       numericCast(remotes), flags)
}

@_transparent
internal func process_vm_writev(_ process: pid_t, _ local: UnsafePointer<iovec>,
                                _ locals: UInt, _ remote: UnsafePointer<iovec>,
                                _ remotes: UInt, _ flags: UInt) -> Int {
  dsx_process_vm_writev(process, local, numericCast(locals), remote,
                        numericCast(remotes), flags)
}
#endif

/// Linux encodes a ptrace event in bits 16 and above of the wait status.
@_transparent
internal func ptraceevent(_ status: CInt) -> CInt {
  status >> 16
}

@_transparent
internal var PTRACE_CONT: CInt {
  7
}

@_transparent
internal var PTRACE_TRACEME: CInt {
  0
}

@_transparent
internal var PTRACE_SINGLESTEP: CInt {
  9
}

@_transparent
internal var PTRACE_ATTACH: CInt {
  16
}

@_transparent
internal var PTRACE_DETACH: CInt {
  17
}

@_transparent
internal var PTRACE_SETOPTIONS: CInt {
  0x4200
}

@_transparent
internal var PTRACE_GETEVENTMSG: CInt {
  0x4201
}

@_transparent
internal var PTRACE_GETSIGINFO: CInt {
  0x4202
}

@_transparent
internal var PTRACE_SYSCALL: CInt {
  24
}

@_transparent
internal var SI_KERNEL: CInt {
  0x80
}

@_transparent
internal var SI_TKILL: CInt {
  -6
}

@_transparent
internal var TRAP_BRKPT: CInt {
  1
}

@_transparent
internal var TRAP_TRACE: CInt {
  2
}

@_transparent
internal var TRAP_HWBKPT: CInt {
  4
}

@_transparent
internal var kBUS_ADRALN: CInt {
  1
}

@_transparent
internal var kBUS_OBJERR: CInt {
  3
}

@_transparent
internal var kSEGV_MAPERR: CInt {
  1
}

@_transparent
internal var kSEGV_PKUERR: CInt {
  4
}

@_transparent
internal var kSEGV_MTESERR: CInt {
  9
}

@_transparent
internal var PTRACE_PEEKDATA: CInt {
  2
}

@_transparent
internal var PTRACE_PEEKTEXT: CInt {
  1
}

@_transparent
internal var PTRACE_POKEDATA: CInt {
  5
}

@_transparent
internal var PTRACE_POKETEXT: CInt {
  4
}

@_transparent
internal var PTRACE_PEEKUSER: CInt {
  3
}

@_transparent
internal var PTRACE_POKEUSER: CInt {
  6
}

@_transparent
internal var PTRACE_GETREGSET: CInt {
  0x4204
}

@_transparent
internal var PTRACE_SETREGSET: CInt {
  0x4205
}

@_transparent
internal var NT_PRSTATUS: Int {
  1
}

@_transparent
internal var NT_FPREGSET: Int {
  2
}

@_transparent
internal var PTRACE_EVENT_FORK: CInt {
  1
}

@_transparent
internal var PTRACE_EVENT_VFORK: CInt {
  2
}

@_transparent
internal var PTRACE_EVENT_CLONE: CInt {
  3
}

@_transparent
internal var PTRACE_EVENT_EXEC: CInt {
  4
}

@_transparent
internal var PTRACE_EVENT_VFORK_DONE: CInt {
  5
}

@_transparent
internal var PTRACE_EVENT_EXIT: CInt {
  6
}

@_transparent
internal var PTRACE_EVENT_STOP: CInt {
  128
}

@_transparent
internal var PTRACE_O_TRACESYSGOOD: UInt {
  0x0000_0001
}

@_transparent
internal var PTRACE_O_TRACEFORK: UInt {
  0x0000_0002
}

@_transparent
internal var PTRACE_O_TRACEVFORK: UInt {
  0x0000_0004
}

@_transparent
internal var PTRACE_O_TRACECLONE: UInt {
  0x0000_0008
}

@_transparent
internal var PTRACE_O_TRACEEXEC: UInt {
  0x0000_0010
}

@_transparent
internal var PTRACE_O_TRACEVFORKDONE: UInt {
  0x0000_0020
}

@_transparent
internal var PTRACE_O_TRACEEXIT: UInt {
  0x0000_0040
}

@_transparent
internal var __WALL: CInt {
#if os(Android)
  CInt(Android.__WALL)
#else
  CInt(Glibc.__WALL)
#endif
}
#endif
