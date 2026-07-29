// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

extension Debuggee.Output {
  internal init?(_ descriptor: CInt?) throws(Debuggee.Error) {
    guard let descriptor else {
      return nil
    }
    self.init()
    let count = withUnsafeMutableBytes(of: &bytes) { bytes in
      read(descriptor, bytes.baseAddress, bytes.count)
    }
    switch count {
    case 1...:
      self.count = count
    case 0:
      return nil
    default:
      switch errno {
      case EAGAIN, EWOULDBLOCK, EINTR, EIO: return nil
      default: throw Debuggee.Error(unix: errno)
      }
    }
  }
}
#endif
