// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension FileFailure {
  /// GDB File-I/O errno values, also decoded by LLDB's host-I/O client.
  internal var code: UInt16 {
    switch self {
    case .permission: 1
    case .missing: 2
    case .interrupted: 4
    case .io: 5
    case .descriptor: 9
    case .access: 13
    case .address: 14
    case .busy: 16
    case .exists: 17
    case .device: 19
    case .directory: 20
    case .folder: 21
    case .invalid: 22
    case .system: 23
    case .process: 24
    case .large: 27
    case .space: 28
    case .seek: 29
    case .readonly: 30
    case .unsupported: 88
    case .length: 91
    case .unknown: 9999
    }
  }
}
