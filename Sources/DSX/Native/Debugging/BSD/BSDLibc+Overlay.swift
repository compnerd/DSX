// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import DSXShims
internal import Glibc

internal func ptrace(_ request: CInt, _ process: pid_t,
                     _ address: UnsafeMutablePointer<CChar>?,
                     _ data: CInt) -> CInt {
  dsx_ptrace(request, process, address, data)
}

@_transparent
internal var PT_CONTINUE: CInt {
  CInt(Glibc.PT_CONTINUE)
}

@_transparent
internal var PT_STEP: CInt {
  CInt(Glibc.PT_STEP)
}

@_transparent
internal var PT_ATTACH: CInt {
  CInt(Glibc.PT_ATTACH)
}

@_transparent
internal var PT_DETACH: CInt {
  CInt(Glibc.PT_DETACH)
}

@_transparent
internal var PT_TRACE_ME: CInt {
  CInt(Glibc.PT_TRACE_ME)
}

@_transparent
internal var PT_IO: CInt {
  CInt(Glibc.PT_IO)
}

@_transparent
internal var PIOD_READ_D: CInt {
  CInt(Glibc.PIOD_READ_D)
}

@_transparent
internal var PIOD_WRITE_D: CInt {
  CInt(Glibc.PIOD_WRITE_D)
}

@_transparent
internal var PT_GETREGS: CInt {
  CInt(Glibc.PT_GETREGS)
}

@_transparent
internal var PT_SETREGS: CInt {
  CInt(Glibc.PT_SETREGS)
}

@_transparent
internal var PT_GETFPREGS: CInt {
  CInt(Glibc.PT_GETFPREGS)
}

@_transparent
internal var PT_SETFPREGS: CInt {
  CInt(Glibc.PT_SETFPREGS)
}

#if os(FreeBSD)
@_transparent
internal var PT_GETNUMLWPS: CInt {
  CInt(Glibc.PT_GETNUMLWPS)
}

@_transparent
internal var PT_GETLWPLIST: CInt {
  CInt(Glibc.PT_GETLWPLIST)
}

@_transparent
internal var PT_GETDBREGS: CInt {
  CInt(Glibc.PT_GETDBREGS)
}

@_transparent
internal var PT_SETDBREGS: CInt {
  CInt(Glibc.PT_SETDBREGS)
}

@_transparent
internal var DBREG_DR6_BMASK: UInt64 {
  UInt64(Glibc.DBREG_DR6_BMASK)
}

@_transparent
internal var DBREG_DR7_LOCAL_ENABLE: UInt64 {
  UInt64(Glibc.DBREG_DR7_LOCAL_ENABLE)
}
#elseif os(OpenBSD)
@_transparent
internal var PT_GET_THREAD_FIRST: CInt {
  CInt(Glibc.PT_GET_THREAD_FIRST)
}

@_transparent
internal var PT_GET_THREAD_NEXT: CInt {
  CInt(Glibc.PT_GET_THREAD_NEXT)
}
#endif
#endif
