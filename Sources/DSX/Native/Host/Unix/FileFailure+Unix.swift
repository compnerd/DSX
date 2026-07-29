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

extension FileFailure {
  internal init(native code: CInt) {
    self = switch code {
    case EPERM: .permission
    case ENOENT: .missing
    case EINTR: .interrupted
    case EIO: .io
    case EBADF: .descriptor
    case EACCES: .access
    case EFAULT: .address
    case EBUSY: .busy
    case EEXIST: .exists
    case ENODEV: .device
    case ENOTDIR: .directory
    case EISDIR: .folder
    case EINVAL: .invalid
    case ENFILE: .system
    case EMFILE: .process
    case EFBIG: .large
    case ENOSPC: .space
    case ESPIPE: .seek
    case EROFS: .readonly
    case ENOSYS, ENOTSUP: .unsupported
    case ENAMETOOLONG: .length
    default: .unknown
    }
  }
}
#endif
