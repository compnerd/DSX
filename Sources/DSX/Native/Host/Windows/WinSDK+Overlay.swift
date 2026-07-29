// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK
internal import DSXShims

#if _pointerBitWidth(_32)
extension DWORD {
  @_transparent
  internal init(bitPattern value: CInt) {
    self = DWORD(UInt32(bitPattern: value))
  }
}

extension CInt {
  @_transparent
  internal init(bitPattern value: DWORD) {
    self = CInt(bitPattern: UInt32(value))
  }
}
#endif

/// Failure sentinel returned by `SuspendThread` and `ResumeThread`.
internal let kThreadSuspendFailure = DWORD.max

/// Status codes used by the Win32 x86 emulation subsystem. See ntstatus.h.
internal let kStatusWX86SingleStep: DWORD = 0x4000001e
internal let kStatusWX86Breakpoint: DWORD = 0x4000001f

#if arch(i386) || arch(x86_64)
/// EFLAGS.TF, the trap flag at bit 8. See Intel® SDM, EFLAGS register.
internal let kEFlagsTrap: DWORD = 1 << 8
#elseif arch(arm) || arch(arm64)
/// CPSR.SS, the software-step flag at bit 21. See Arm® ARM, CPSR.
internal let kCPSRSoftwareStep: DWORD = 1 << 21
#endif

#if arch(arm64)
@_transparent
internal var ARM64_MAX_BREAKPOINTS: Int {
  Int(WinSDK.ARM64_MAX_BREAKPOINTS)
}

@_transparent
internal var ARM64_MAX_WATCHPOINTS: Int {
  Int(WinSDK.ARM64_MAX_WATCHPOINTS)
}
#endif

@_transparent
internal var CREATE_ALWAYS: DWORD {
  DWORD(WinSDK.CREATE_ALWAYS)
}

@_transparent
internal var CREATE_NEW: DWORD {
  DWORD(WinSDK.CREATE_NEW)
}

@_transparent
internal var CREATE_NEW_PROCESS_GROUP: DWORD {
  DWORD(WinSDK.CREATE_NEW_PROCESS_GROUP)
}

@_transparent
internal var CREATE_NO_WINDOW: DWORD {
  DWORD(WinSDK.CREATE_NO_WINDOW)
}

@_transparent
internal var CREATE_PROCESS_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.CREATE_PROCESS_DEBUG_EVENT)
}

@_transparent
internal var CREATE_THREAD_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.CREATE_THREAD_DEBUG_EVENT)
}

@_transparent
internal var CREATE_UNICODE_ENVIRONMENT: DWORD {
  DWORD(WinSDK.CREATE_UNICODE_ENVIRONMENT)
}

@_transparent
internal var CP_UTF8: UINT {
  UINT(WinSDK.CP_UTF8)
}

@_transparent
internal var EXTENDED_STARTUPINFO_PRESENT: DWORD {
  DWORD(WinSDK.EXTENDED_STARTUPINFO_PRESENT)
}

@_transparent
internal var PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD_PTR {
  DWORD_PTR(WinSDK.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE)
}

@_transparent
internal var PROC_THREAD_ATTRIBUTE_HANDLE_LIST: DWORD_PTR {
  dsx_proc_thread_attribute_handle_list()
}

@_transparent
internal var CSTR_EQUAL: CInt {
  CInt(WinSDK.CSTR_EQUAL)
}

@_transparent
internal var DETACHED_PROCESS: DWORD {
  DWORD(WinSDK.DETACHED_PROCESS)
}

@_transparent
internal var CONTEXT_CONTROL: DWORD {
  DWORD(WinSDK.CONTEXT_CONTROL)
}

@_transparent
internal var CONTEXT_FLOATING_POINT: DWORD {
  DWORD(WinSDK.CONTEXT_FLOATING_POINT)
}

@_transparent
internal var CONTEXT_DEBUG_REGISTERS: DWORD {
  DWORD(WinSDK.CONTEXT_DEBUG_REGISTERS)
}

@_transparent
internal var CONTEXT_INTEGER: DWORD {
  DWORD(WinSDK.CONTEXT_INTEGER)
}

#if arch(arm64)
@_transparent
internal var CONTEXT_X18: DWORD {
  DWORD(0x00400010)
}

@_transparent
internal var CONTEXT_ALL: DWORD {
  let base = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_FLOATING_POINT
  return base | CONTEXT_DEBUG_REGISTERS | CONTEXT_X18
}
#elseif arch(i386) || arch(x86_64)
@_transparent
internal var CONTEXT_SEGMENTS: DWORD {
  DWORD(WinSDK.CONTEXT_SEGMENTS)
}

@_transparent
internal var CONTEXT_ALL: DWORD {
  let base = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_SEGMENTS
  return base | CONTEXT_FLOATING_POINT | CONTEXT_DEBUG_REGISTERS
}
#endif

@_transparent
internal var DBG_CONTINUE: DWORD {
  DWORD(WinSDK.DBG_CONTINUE)
}

@_transparent
internal var DBG_EXCEPTION_NOT_HANDLED: DWORD {
  DWORD(WinSDK.DBG_EXCEPTION_NOT_HANDLED)
}

@_transparent
internal var ERROR_SEM_TIMEOUT: DWORD {
  DWORD(WinSDK.ERROR_SEM_TIMEOUT)
}

@_transparent
internal var DEBUG_ONLY_THIS_PROCESS: DWORD {
  DWORD(WinSDK.DEBUG_ONLY_THIS_PROCESS)
}

@_transparent
internal var EXCEPTION_ACCESS_VIOLATION: DWORD {
  DWORD(WinSDK.EXCEPTION_ACCESS_VIOLATION)
}

@_transparent
internal var EXCEPTION_BREAKPOINT: DWORD {
  DWORD(WinSDK.EXCEPTION_BREAKPOINT)
}

@_transparent
internal var EXCEPTION_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.EXCEPTION_DEBUG_EVENT)
}

@_transparent
internal var EXCEPTION_SINGLE_STEP: DWORD {
  DWORD(WinSDK.EXCEPTION_SINGLE_STEP)
}

@_transparent
internal var EXIT_PROCESS_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.EXIT_PROCESS_DEBUG_EVENT)
}

@_transparent
internal var EXIT_THREAD_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.EXIT_THREAD_DEBUG_EVENT)
}

@_transparent
internal var ERROR_ACCESS_DENIED: DWORD {
  DWORD(WinSDK.ERROR_ACCESS_DENIED)
}

@_transparent
internal var ERROR_ALREADY_EXISTS: DWORD {
  DWORD(WinSDK.ERROR_ALREADY_EXISTS)
}

@_transparent
internal var ERROR_ARITHMETIC_OVERFLOW: DWORD {
  DWORD(WinSDK.ERROR_ARITHMETIC_OVERFLOW)
}

@_transparent
internal var ERROR_BAD_UNIT: DWORD {
  DWORD(WinSDK.ERROR_BAD_UNIT)
}

@_transparent
internal var ERROR_BUSY: DWORD {
  DWORD(WinSDK.ERROR_BUSY)
}

@_transparent
internal var ERROR_CALL_NOT_IMPLEMENTED: DWORD {
  DWORD(WinSDK.ERROR_CALL_NOT_IMPLEMENTED)
}

@_transparent
internal var ERROR_DEV_NOT_EXIST: DWORD {
  DWORD(WinSDK.ERROR_DEV_NOT_EXIST)
}

@_transparent
internal var ERROR_DIRECTORY: DWORD {
  DWORD(WinSDK.ERROR_DIRECTORY)
}

@_transparent
internal var ERROR_DISK_FULL: DWORD {
  DWORD(WinSDK.ERROR_DISK_FULL)
}

@_transparent
internal var ERROR_FILE_NOT_FOUND: DWORD {
  DWORD(WinSDK.ERROR_FILE_NOT_FOUND)
}

@_transparent
internal var ERROR_FILE_EXISTS: DWORD {
  DWORD(WinSDK.ERROR_FILE_EXISTS)
}

@_transparent
internal var ERROR_FILE_TOO_LARGE: DWORD {
  DWORD(WinSDK.ERROR_FILE_TOO_LARGE)
}

@_transparent
internal var ERROR_FILENAME_EXCED_RANGE: DWORD {
  DWORD(WinSDK.ERROR_FILENAME_EXCED_RANGE)
}

@_transparent
internal var ERROR_HANDLE_DISK_FULL: DWORD {
  DWORD(WinSDK.ERROR_HANDLE_DISK_FULL)
}

@_transparent
internal var ERROR_INVALID_ADDRESS: DWORD {
  DWORD(WinSDK.ERROR_INVALID_ADDRESS)
}

@_transparent
internal var ERROR_INVALID_DRIVE: DWORD {
  DWORD(WinSDK.ERROR_INVALID_DRIVE)
}

@_transparent
internal var ERROR_INVALID_HANDLE: DWORD {
  DWORD(WinSDK.ERROR_INVALID_HANDLE)
}

@_transparent
internal var ERROR_INVALID_NAME: DWORD {
  DWORD(WinSDK.ERROR_INVALID_NAME)
}

@_transparent
internal var ERROR_INVALID_PARAMETER: DWORD {
  DWORD(WinSDK.ERROR_INVALID_PARAMETER)
}

@_transparent
internal var ERROR_INVALID_REPARSE_DATA: DWORD {
  DWORD(WinSDK.ERROR_INVALID_REPARSE_DATA)
}

@_transparent
internal var ERROR_IO_DEVICE: DWORD {
  DWORD(WinSDK.ERROR_IO_DEVICE)
}

@_transparent
internal var ERROR_LOCK_VIOLATION: DWORD {
  DWORD(WinSDK.ERROR_LOCK_VIOLATION)
}

@_transparent
internal var ERROR_NOACCESS: DWORD {
  DWORD(WinSDK.ERROR_NOACCESS)
}

@_transparent
internal var ERROR_NOT_FOUND: DWORD {
  DWORD(WinSDK.ERROR_NOT_FOUND)
}

@_transparent
internal var ERROR_NOT_ENOUGH_MEMORY: DWORD {
  DWORD(WinSDK.ERROR_NOT_ENOUGH_MEMORY)
}

@_transparent
internal var ERROR_NOT_A_REPARSE_POINT: DWORD {
  DWORD(WinSDK.ERROR_NOT_A_REPARSE_POINT)
}

@_transparent
internal var ERROR_NOT_SUPPORTED: DWORD {
  DWORD(WinSDK.ERROR_NOT_SUPPORTED)
}

@_transparent
internal var ERROR_NO_MORE_FILES: DWORD {
  DWORD(WinSDK.ERROR_NO_MORE_FILES)
}

@_transparent
internal var ERROR_OPERATION_ABORTED: DWORD {
  DWORD(WinSDK.ERROR_OPERATION_ABORTED)
}

@_transparent
internal var ERROR_PARTIAL_COPY: DWORD {
  DWORD(WinSDK.ERROR_PARTIAL_COPY)
}

@_transparent
internal var ERROR_PATH_NOT_FOUND: DWORD {
  DWORD(WinSDK.ERROR_PATH_NOT_FOUND)
}

@_transparent
internal var ERROR_PRIVILEGE_NOT_HELD: DWORD {
  DWORD(WinSDK.ERROR_PRIVILEGE_NOT_HELD)
}

@_transparent
internal var ERROR_READ_FAULT: DWORD {
  DWORD(WinSDK.ERROR_READ_FAULT)
}

@_transparent
internal var ERROR_SEEK: DWORD {
  DWORD(WinSDK.ERROR_SEEK)
}

@_transparent
internal var ERROR_SHARING_VIOLATION: DWORD {
  DWORD(WinSDK.ERROR_SHARING_VIOLATION)
}

@_transparent
internal var ERROR_TOO_MANY_OPEN_FILES: DWORD {
  DWORD(WinSDK.ERROR_TOO_MANY_OPEN_FILES)
}

@_transparent
internal var ERROR_WRITE_FAULT: DWORD {
  DWORD(WinSDK.ERROR_WRITE_FAULT)
}

@_transparent
internal var ERROR_WRITE_PROTECT: DWORD {
  DWORD(WinSDK.ERROR_WRITE_PROTECT)
}

@_transparent
internal var FILE_ATTRIBUTE_DIRECTORY: DWORD {
  DWORD(WinSDK.FILE_ATTRIBUTE_DIRECTORY)
}

@_transparent
internal var FILE_ATTRIBUTE_REPARSE_POINT: DWORD {
  DWORD(WinSDK.FILE_ATTRIBUTE_REPARSE_POINT)
}

@_transparent
internal var FILE_ATTRIBUTE_NORMAL: DWORD {
  DWORD(WinSDK.FILE_ATTRIBUTE_NORMAL)
}

@_transparent
internal var FILE_FLAG_BACKUP_SEMANTICS: DWORD {
  DWORD(WinSDK.FILE_FLAG_BACKUP_SEMANTICS)
}

@_transparent
internal var FILE_FLAG_OPEN_REPARSE_POINT: DWORD {
  DWORD(WinSDK.FILE_FLAG_OPEN_REPARSE_POINT)
}

@_transparent
internal var SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE: DWORD {
  DWORD(WinSDK.SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)
}

@_transparent
internal var SYMBOLIC_LINK_FLAG_DIRECTORY: DWORD {
  DWORD(WinSDK.SYMBOLIC_LINK_FLAG_DIRECTORY)
}

@_transparent
internal var FORMAT_MESSAGE_FROM_SYSTEM: DWORD {
  DWORD(WinSDK.FORMAT_MESSAGE_FROM_SYSTEM)
}

@_transparent
internal var FORMAT_MESSAGE_IGNORE_INSERTS: DWORD {
  DWORD(WinSDK.FORMAT_MESSAGE_IGNORE_INSERTS)
}

@_transparent
internal var FILE_BEGIN: DWORD {
  DWORD(WinSDK.FILE_BEGIN)
}

@_transparent
internal var FILE_MAP_READ: DWORD {
  DWORD(WinSDK.FILE_MAP_READ)
}

@_transparent
internal var FILE_END: DWORD {
  DWORD(WinSDK.FILE_END)
}

@_transparent
internal var FILE_NAME_NORMALIZED: DWORD {
  DWORD(WinSDK.FILE_NAME_NORMALIZED)
}

@_transparent
internal var FILE_SHARE_DELETE: DWORD {
  DWORD(WinSDK.FILE_SHARE_DELETE)
}

@_transparent
internal var FILE_SHARE_READ: DWORD {
  DWORD(WinSDK.FILE_SHARE_READ)
}

@_transparent
internal var FILE_SHARE_WRITE: DWORD {
  DWORD(WinSDK.FILE_SHARE_WRITE)
}

@_transparent
internal var FSCTL_GET_REPARSE_POINT: DWORD {
  DWORD(WinSDK.FSCTL_GET_REPARSE_POINT)
}

@_transparent
internal var FSCTL_SET_REPARSE_POINT: DWORD {
  DWORD(WinSDK.FSCTL_SET_REPARSE_POINT)
}

@_transparent
internal var GENERIC_READ: DWORD {
  DWORD(WinSDK.GENERIC_READ)
}

@_transparent
internal var GENERIC_WRITE: DWORD {
  DWORD(WinSDK.GENERIC_WRITE)
}

@_transparent
internal var INFINITE: DWORD {
  DWORD(WinSDK.INFINITE)
}

@_transparent
internal var THREAD_GET_CONTEXT: DWORD {
  DWORD(WinSDK.THREAD_GET_CONTEXT)
}

@_transparent
internal var THREAD_QUERY_INFORMATION: DWORD {
  DWORD(WinSDK.THREAD_QUERY_INFORMATION)
}

@_transparent
internal var THREAD_SET_CONTEXT: DWORD {
  DWORD(WinSDK.THREAD_SET_CONTEXT)
}

@_transparent
internal var LOAD_DLL_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.LOAD_DLL_DEBUG_EVENT)
}

@_transparent
internal var IMAGE_FILE_MACHINE_AMD64: USHORT {
  USHORT(WinSDK.IMAGE_FILE_MACHINE_AMD64)
}

@_transparent
internal var IMAGE_FILE_MACHINE_ARM: USHORT {
  USHORT(WinSDK.IMAGE_FILE_MACHINE_ARM)
}

@_transparent
internal var IMAGE_FILE_MACHINE_ARM64: USHORT {
  USHORT(WinSDK.IMAGE_FILE_MACHINE_ARM64)
}

@_transparent
internal var IMAGE_FILE_MACHINE_I386: USHORT {
  USHORT(WinSDK.IMAGE_FILE_MACHINE_I386)
}

@_transparent
internal var IMAGE_FILE_MACHINE_UNKNOWN: USHORT {
  USHORT(WinSDK.IMAGE_FILE_MACHINE_UNKNOWN)
}

@_transparent
internal var INVALID_HANDLE_VALUE: HANDLE {
  WinSDK.INVALID_HANDLE_VALUE
}

@_transparent
internal var IO_REPARSE_TAG_MOUNT_POINT: DWORD {
  DWORD(WinSDK.IO_REPARSE_TAG_MOUNT_POINT)
}

@_transparent
internal var IO_REPARSE_TAG_SYMLINK: DWORD {
  DWORD(WinSDK.IO_REPARSE_TAG_SYMLINK)
}

@_transparent
internal var IPPROTO_IPV6: CInt {
  CInt(WinSDK.IPPROTO_IPV6.rawValue)
}

@_transparent
internal var IPPROTO_TCP: CInt {
  CInt(WinSDK.IPPROTO_TCP.rawValue)
}

@_transparent
internal var TCP_NODELAY: CInt {
  CInt(WinSDK.TCP_NODELAY)
}

@_transparent
internal var MEM_COMMIT: DWORD {
  DWORD(WinSDK.MEM_COMMIT)
}

@_transparent
internal var MEM_RELEASE: DWORD {
  DWORD(WinSDK.MEM_RELEASE)
}

@_transparent
internal var MEM_RESERVE: DWORD {
  DWORD(WinSDK.MEM_RESERVE)
}

@_transparent
internal var OPEN_ALWAYS: DWORD {
  DWORD(WinSDK.OPEN_ALWAYS)
}

@_transparent
internal var OPEN_EXISTING: DWORD {
  DWORD(WinSDK.OPEN_EXISTING)
}

@_transparent
internal var STARTF_USESTDHANDLES: DWORD {
  DWORD(WinSDK.STARTF_USESTDHANDLES)
}

@_transparent
internal var HANDLE_FLAG_INHERIT: DWORD {
  DWORD(WinSDK.HANDLE_FLAG_INHERIT)
}

@_transparent
internal var STD_ERROR_HANDLE: DWORD {
  DWORD(WinSDK.STD_ERROR_HANDLE)
}

@_transparent
internal var STD_INPUT_HANDLE: DWORD {
  DWORD(WinSDK.STD_INPUT_HANDLE)
}

@_transparent
internal var STD_OUTPUT_HANDLE: DWORD {
  DWORD(WinSDK.STD_OUTPUT_HANDLE)
}

@_transparent
internal var STILL_ACTIVE: DWORD {
  DWORD(WinSDK.STILL_ACTIVE)
}

@_transparent
internal var TH32CS_SNAPMODULE: DWORD {
  DWORD(WinSDK.TH32CS_SNAPMODULE)
}

@_transparent
internal var TH32CS_SNAPMODULE32: DWORD {
  DWORD(WinSDK.TH32CS_SNAPMODULE32)
}

@_transparent
internal var PAGE_EXECUTE: DWORD {
  DWORD(WinSDK.PAGE_EXECUTE)
}

@_transparent
internal var PAGE_EXECUTE_READ: DWORD {
  DWORD(WinSDK.PAGE_EXECUTE_READ)
}

@_transparent
internal var PAGE_EXECUTE_READWRITE: DWORD {
  DWORD(WinSDK.PAGE_EXECUTE_READWRITE)
}

@_transparent
internal var PAGE_EXECUTE_WRITECOPY: DWORD {
  DWORD(WinSDK.PAGE_EXECUTE_WRITECOPY)
}

@_transparent
internal var PAGE_GUARD: DWORD {
  DWORD(WinSDK.PAGE_GUARD)
}

@_transparent
internal var PAGE_NOACCESS: DWORD {
  DWORD(WinSDK.PAGE_NOACCESS)
}

@_transparent
internal var PAGE_READONLY: DWORD {
  DWORD(WinSDK.PAGE_READONLY)
}

@_transparent
internal var PAGE_READWRITE: DWORD {
  DWORD(WinSDK.PAGE_READWRITE)
}

@_transparent
internal var PAGE_WRITECOPY: DWORD {
  DWORD(WinSDK.PAGE_WRITECOPY)
}

@_transparent
internal var PATHCCH_ALLOW_LONG_PATHS: ULONG {
  ULONG(WinSDK.PATHCCH_ALLOW_LONG_PATHS.rawValue)
}

@_transparent
internal var PATHCCH_CANONICALIZE_SLASHES: ULONG {
  ULONG(WinSDK.PATHCCH_CANONICALIZE_SLASHES.rawValue)
}

@_transparent
internal var PATHCCH_ENSURE_TRAILING_SLASH: ULONG {
  ULONG(WinSDK.PATHCCH_ENSURE_TRAILING_SLASH.rawValue)
}

@_transparent
internal var PROCESS_QUERY_LIMITED_INFORMATION: DWORD {
  DWORD(WinSDK.PROCESS_QUERY_LIMITED_INFORMATION)
}

@_transparent
internal var PROCESS_CREATE_THREAD: DWORD {
  DWORD(WinSDK.PROCESS_CREATE_THREAD)
}

@_transparent
internal var PROCESS_TERMINATE: DWORD {
  DWORD(WinSDK.PROCESS_TERMINATE)
}

@_transparent
internal var SYNCHRONIZE: DWORD {
  DWORD(WinSDK.SYNCHRONIZE)
}

@_transparent
internal var WAIT_OBJECT_0: DWORD {
  DWORD(WinSDK.WAIT_OBJECT_0)
}

@_transparent
internal var WAIT_TIMEOUT: DWORD {
  DWORD(WinSDK.WAIT_TIMEOUT)
}

@_transparent
internal var PROCESS_VM_OPERATION: DWORD {
  DWORD(WinSDK.PROCESS_VM_OPERATION)
}

@_transparent
internal var PROCESS_VM_READ: DWORD {
  DWORD(WinSDK.PROCESS_VM_READ)
}

@_transparent
internal var PROCESS_VM_WRITE: DWORD {
  DWORD(WinSDK.PROCESS_VM_WRITE)
}

@_transparent
internal var TH32CS_SNAPPROCESS: DWORD {
  DWORD(WinSDK.TH32CS_SNAPPROCESS)
}

@_transparent
internal var UNLOAD_DLL_DEBUG_EVENT: DWORD {
  DWORD(WinSDK.UNLOAD_DLL_DEBUG_EVENT)
}

@_transparent
internal var VOLUME_NAME_DOS: DWORD {
  DWORD(WinSDK.VOLUME_NAME_DOS)
}

@_transparent
internal var OUTPUT_DEBUG_STRING_EVENT: DWORD {
  DWORD(WinSDK.OUTPUT_DEBUG_STRING_EVENT)
}

@_transparent
internal var TH32CS_SNAPTHREAD: DWORD {
  DWORD(WinSDK.TH32CS_SNAPTHREAD)
}

@_transparent
internal var THREAD_QUERY_LIMITED_INFORMATION: DWORD {
  DWORD(WinSDK.THREAD_QUERY_LIMITED_INFORMATION)
}

@_transparent
internal var TRUNCATE_EXISTING: DWORD {
  DWORD(WinSDK.TRUNCATE_EXISTING)
}
#endif
