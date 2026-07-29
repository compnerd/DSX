// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension UnsafeMutableRawBufferPointer {
  /// Transfers a regset while preserving the kernel's returned byte count.
  @discardableResult
  internal func transfer(_ request: CInt, note: Int, thread: pid_t,
                         complete: Bool = true,
                         failure: (CInt) -> Debuggee.Error =
                             Debuggee.Error.init(register:))
      throws(Debuggee.Error) -> Int {
    var vector = iovec(iov_base: baseAddress, iov_len: numericCast(count))
    let result = withUnsafeMutablePointer(to: &vector) { vector in
      ptrace(request, thread, UnsafeMutableRawPointer(bitPattern: note),
             UnsafeMutableRawPointer(vector))
    }
    guard result == 0 else {
      throw failure(errno)
    }
    let length = Int(vector.iov_len)
    guard length <= count, complete == false || length == count else {
      throw .register
    }
    return length
  }
}
#endif
