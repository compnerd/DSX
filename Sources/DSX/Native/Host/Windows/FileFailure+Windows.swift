// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension FileFailure {
  internal init(native code: CInt) {
    self = switch DWORD(bitPattern: code) {
    case ERROR_PRIVILEGE_NOT_HELD: .permission
    case ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND,
         ERROR_INVALID_DRIVE: .missing
    case ERROR_OPERATION_ABORTED: .interrupted
    case ERROR_READ_FAULT, ERROR_WRITE_FAULT, ERROR_IO_DEVICE: .io
    case ERROR_INVALID_HANDLE: .descriptor
    case ERROR_ACCESS_DENIED: .access
    case ERROR_NOACCESS: .address
    case ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION, ERROR_BUSY: .busy
    case ERROR_FILE_EXISTS, ERROR_ALREADY_EXISTS: .exists
    case ERROR_BAD_UNIT, ERROR_DEV_NOT_EXIST: .device
    case ERROR_DIRECTORY: .directory
    case ERROR_INVALID_PARAMETER, ERROR_INVALID_NAME: .invalid
    case ERROR_TOO_MANY_OPEN_FILES: .process
    case ERROR_FILE_TOO_LARGE, ERROR_ARITHMETIC_OVERFLOW: .large
    case ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL: .space
    case ERROR_SEEK: .seek
    case ERROR_WRITE_PROTECT: .readonly
    case ERROR_NOT_SUPPORTED, ERROR_CALL_NOT_IMPLEMENTED: .unsupported
    case ERROR_FILENAME_EXCED_RANGE: .length
    default: .unknown
    }
  }
}
#endif
