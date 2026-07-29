// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

/// Pins the selected filesystem independently of the process's lifetime.
internal struct LinuxFileRoot: ~Copyable, Sendable {
  private let descriptor: CInt

  internal init(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    guard process.rawValue > 0, process.rawValue <= UInt64(pid_t.max) else {
      throw .process
    }
    let path = "/proc/\(process.rawValue)/root"
    let flags = O_PATH | O_DIRECTORY | O_CLOEXEC
    let descriptor = path.withCString { DSX::open($0, flags, 0) }
    guard descriptor >= 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
    self.descriptor = descriptor
  }

  deinit {
    _ = DSX::close(descriptor)
  }

  internal borrowing func open(_ path: String, flags: CInt, mode: mode_t = 0)
      throws(Debuggee.Error) -> CInt {
    // Unlike a /proc/PID/root prefix, IN_ROOT also roots absolute symlinks
    // and clamps ".." at the selected root without changing the host process.
    var how = open_how()
    how.flags = UInt64(flags | O_CLOEXEC)
    how.mode = flags & O_CREAT == 0 ? 0 : UInt64(mode & 0o7777)
    how.resolve = RESOLVE_IN_ROOT | RESOLVE_NO_MAGICLINKS
    let result = path.withCString { path in
      openat2(descriptor, path, &how, MemoryLayout<open_how>.size)
    }
    guard result >= 0 else {
      // No unrooted fallback: older kernels cannot provide these semantics.
      if errno == ENOSYS {
        throw .unsupported
      }
      throw Debuggee.Error(filesystem: errno)
    }
    return result
  }
}

/// Owns the resolved parent while a non-following pathname operation executes.
internal struct LinuxFileLocation: ~Copyable {
  private let descriptor: CInt
  private let name: String

  internal init(_ path: String, root: borrowing LinuxFileRoot)
      throws(Debuggee.Error) {
    guard !path.isEmpty else {
      throw Debuggee.Error(filesystem: ENOENT)
    }
    let empty = path.drop(while: { $0 == "/" }).isEmpty
    let end = path.lastIndex(where: { $0 != "/" }) ?? path.startIndex
    let separator = path[..<end].lastIndex(of: "/")
    let location: (String, String) = switch (empty, separator) {
    case (true, _):
      ("/", ".")
    case (false, .some(let separator)):
      (separator == path.startIndex ? "/" : String(path[..<separator]),
       String(path[path.index(after: separator)...]))
    case (false, .none):
      (".", path)
    }
    let descriptor = try root.open(location.0, flags: O_PATH | O_DIRECTORY)
    self.descriptor = descriptor
    name = location.1
  }

  internal borrowing func remove() throws(Debuggee.Error) {
    let status = name.withCString { path in
      unlinkat(descriptor, path, 0)
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  internal borrowing func link(_ target: String) throws(Debuggee.Error) {
    let status = target.withCString { target in
      name.withCString { path in
        symlinkat(target, descriptor, path)
      }
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  deinit {
    _ = DSX::close(descriptor)
  }
}
#endif
