// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif
internal import DSXShims

/// Function-like wait macros are not imported by ClangImporter. These values
/// implement the wait status layout used by Darwin and the supported Unix
/// libc implementations.
internal let kWaitSignalMask: CInt = 0x7f
internal let kWaitStopped: CInt = 0x7f
internal let kWaitStatusShift: CInt = 8
internal let kWaitStatusMask: CInt = 0xff

#if os(Android)
@_transparent
internal var MAP_FAILED: UnsafeMutableRawPointer? {
  UnsafeMutableRawPointer(bitPattern: -1)
}
#endif

@_transparent
internal func timestamps(_ value: stat)
    -> (access: time_t, modification: time_t, change: time_t) {
#if os(anyAppleOS)
  (value.st_atimespec.tv_sec, value.st_mtimespec.tv_sec,
   value.st_ctimespec.tv_sec)
#else
  (value.st_atim.tv_sec, value.st_mtim.tv_sec, value.st_ctim.tv_sec)
#endif
}

@_transparent
internal func variables() -> UnixSpawnPointer? {
#if os(Android) || os(Linux)
  dsx_environment()
#else
  environ
#endif
}

#if !os(anyAppleOS)
internal typealias SpawnActions = UnsafeMutablePointer<UnixSpawnFileActions>
internal typealias SpawnPath = UnsafePointer<CChar>

@_transparent
internal func posix_spawn_file_actions_addchdir(_ actions: SpawnActions,
                                                _ path: SpawnPath) -> CInt {
  dsx_spawn_chdir(actions, path)
}
#endif

#endif
