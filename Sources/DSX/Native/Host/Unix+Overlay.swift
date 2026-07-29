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

#if os(anyAppleOS)
internal typealias UnixSpawnFileActions = posix_spawn_file_actions_t?
#else
internal typealias UnixSpawnFileActions = posix_spawn_file_actions_t
#endif

#if !os(anyAppleOS)
@_transparent
internal func pipe2(_ descriptors: UnsafeMutablePointer<CInt>,
                    _ flags: CInt) -> CInt {
  dsx_pipe2(descriptors, flags)
}
#endif

@_transparent
internal func posix_spawnp(_ process: UnsafeMutablePointer<pid_t>,
                           _ path: UnsafePointer<CChar>,
                           _ actions: UnsafePointer<UnixSpawnFileActions>?,
                           _ arguments: UnixSpawnPointer,
                           _ environment: UnixSpawnPointer) -> CInt {
#if os(Android)
  var actions = actions?.pointee
  let argv = UnsafeRawPointer(arguments)
    .assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
  return Android.posix_spawnp(process, path, &actions, nil, argv, environment)
#elseif os(anyAppleOS)
  Darwin.posix_spawnp(process, path, actions, nil, arguments, environment)
#else
  Glibc.posix_spawnp(process, path, actions, nil, arguments, environment)
#endif
}

@_transparent
internal func accept(_ handle: CInt) -> CInt {
#if os(anyAppleOS)
  Darwin.accept(handle, nil, nil)
#elseif os(Android)
  Android.accept(handle, nil, nil)
#else
  Glibc.accept(handle, nil, nil)
#endif
}

@_transparent
internal func close(_ handle: CInt) -> CInt {
#if os(anyAppleOS)
  Darwin.close(handle)
#elseif os(Android)
  Android.close(handle)
#else
  Glibc.close(handle)
#endif
}

@_transparent
internal func fork() -> pid_t {
#if os(anyAppleOS)
  dsx_fork()
#elseif os(Android)
  Android.fork()
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
  Glibc.fork()
#endif
}

@_transparent
internal func _exit(_ status: CInt) -> Never {
#if os(anyAppleOS)
  Darwin._exit(status)
#elseif os(Android)
  Android._exit(status)
#else
  Glibc._exit(status)
#endif
}

@_transparent
internal func connect(_ handle: CInt, _ address: UnsafePointer<sockaddr>,
                      _ length: socklen_t) -> CInt {
#if os(anyAppleOS)
  Darwin.connect(handle, address, length)
#elseif os(Android)
  Android.connect(handle, address, length)
#else
  Glibc.connect(handle, address, length)
#endif
}

@_transparent
internal func listen(_ handle: CInt, _ backlog: CInt) -> CInt {
#if os(anyAppleOS)
  Darwin.listen(handle, backlog)
#elseif os(Android)
  Android.listen(handle, backlog)
#else
  Glibc.listen(handle, backlog)
#endif
}

@_transparent
internal func kill(_ process: pid_t, _ signal: CInt) -> CInt {
#if os(anyAppleOS)
  Darwin.kill(process, signal)
#elseif os(Android)
  Android.kill(process, signal)
#else
  Glibc.kill(process, signal)
#endif
}

@_transparent
internal func open(_ path: UnsafePointer<CChar>, _ flags: CInt) -> CInt {
#if os(anyAppleOS)
  Darwin.open(path, flags)
#elseif os(Android)
  Android.open(path, flags)
#else
  Glibc.open(path, flags)
#endif
}

#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
@_transparent
internal func open(_ path: UnsafePointer<CChar>, _ flags: CInt,
                   _ mode: mode_t) -> CInt {
#if os(anyAppleOS)
  Darwin.open(path, flags, mode)
#else
  Glibc.open(path, flags, mode)
#endif
}
#endif

@_transparent
internal func read(_ handle: CInt, _ bytes: UnsafeMutableRawPointer?,
                   _ count: Int) -> Int {
#if os(anyAppleOS)
  Darwin.read(handle, bytes, count)
#elseif os(Android)
  Android.read(handle, bytes, count)
#else
  Glibc.read(handle, bytes, count)
#endif
}

@_transparent
internal func symlink(_ target: UnsafePointer<CChar>,
                      _ path: UnsafePointer<CChar>) -> CInt {
#if os(anyAppleOS)
  Darwin.symlink(target, path)
#elseif os(Android)
  Android.symlink(target, path)
#else
  Glibc.symlink(target, path)
#endif
}

@_transparent
internal func write(_ handle: CInt, _ bytes: UnsafeRawPointer?,
                    _ count: Int) -> Int {
#if os(anyAppleOS)
  Darwin.write(handle, bytes, count)
#elseif os(Android)
  Android.write(handle, bytes, count)
#else
  Glibc.write(handle, bytes, count)
#endif
}
#endif
