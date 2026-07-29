// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal enum Error: Swift.Error, Equatable, Sendable {
    case access
    case breakpoint
    case checksum
    case denied
    case exited(CInt)
    case file(FileFailure)
    case launch(CInt)
    case premature(CInt)
    case memory
    case process
    case register
    case state
    case system(CInt)
    case thread
    case unsupported
  }
}

extension Debuggee.Error: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .access: "debuggee access denied"
    case .breakpoint: "debuggee breakpoint operation failed"
    case .checksum: "checksum operation failed"
    case .denied: "debuggee denied the requested operation"
    case .exited(let status): "debuggee process exited with status \(status)"
    case .file: "file operation failed"
    case .launch(let code): "debuggee launch failed (\(code))"
    case .premature(let status):
      "debuggee process prematurely exited with status \(status)"
    case .memory: "debuggee memory operation failed"
    case .process: "debuggee process was not found"
    case .register: "debuggee register operation failed"
    case .state: "debuggee is in an invalid state"
    case .system(let code): "debuggee system operation failed (\(code))"
    case .thread: "debuggee thread was not found"
    case .unsupported: "debuggee operation is unsupported"
    }
  }
}
