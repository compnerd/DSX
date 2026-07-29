// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum SessionIsolationError: Error, Equatable, Sendable {
  case system(CInt)
  case unsupported
}

extension SessionIsolationError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .system(let code): "unable to create a server session (\(code))"
    case .unsupported: "session isolation is unsupported on Windows"
    }
  }
}
