// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD)
internal import DSXShims
internal import Glibc
#endif

internal enum CoreDump {
  internal static var capabilities: DebugCapabilities {
#if os(FreeBSD)
    dsx_coredump_supported() == 0 ? DebugCapabilities() : .core
#else
    DebugCapabilities()
#endif
  }
  internal static func dump(_ process: ProcessIdentifier, hint: String?)
      throws(Debuggee.Error) -> String {
#if os(FreeBSD)
    let process = try process.native
    var path = hint ?? ""
    var descriptor: CInt = -1
    if let hint {
      var encoded = Array(hint.utf8CString)
      let flags = O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
      descriptor = encoded.withUnsafeMutableBufferPointer { path in
        dsx_open(path.baseAddress, flags, 0o600)
      }
    }
    if descriptor < 0 {
      path = "/tmp/dsx.XXXXXX.core"
      var encoded = Array(path.utf8CString)
      descriptor = encoded.withUnsafeMutableBufferPointer { path in
        mkstemps(path.baseAddress, 5)
      }
      path = String(decoding: encoded.dropLast(), as: UTF8.self)
    }
    guard descriptor >= 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    guard dsx_coredump(process, descriptor) == 0 else {
      let code = errno
      _ = DSX::close(descriptor)
      path.withCString { path in
        _ = unlink(path)
      }
      throw UnixDebugProcess.failure(code)
    }
    guard DSX::close(descriptor) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    return path
#else
    _ = process
    _ = hint
    throw .unsupported
#endif
  }
}
