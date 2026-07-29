// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT

extension LogSystem {
  internal static var error: CInt {
    STDERR_FILENO
  }

  internal static func open(_ path: String, append: Bool) throws(LogError)
      -> CInt {
    var descriptor: CInt = -1
    let disposition = append ? _O_APPEND : _O_TRUNC
    let access = _O_WRONLY | _O_CREAT | _O_BINARY | _O_NOINHERIT
    let status = withUTF16CString(path) { path in
      _wsopen_s(&descriptor, path, access | disposition, _SH_DENYNO,
                _S_IREAD | _S_IWRITE)
    }
    guard status == 0 else {
      throw .open(CInt(status))
    }
    guard descriptor >= 0 else {
      throw .open(errno)
    }
    return descriptor
  }

  internal static func close(_ descriptor: CInt) {
    _ = _close(descriptor)
  }

  internal static func terminal(_ descriptor: CInt) -> Bool {
    _isatty(descriptor) != 0
  }

  internal static func output(_ descriptor: CInt, _ buffer: UnsafeRawPointer,
                              _ count: Int) -> Int {
    Int(_write(descriptor, buffer, UInt32(count)))
  }
}
#endif
