// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum DaemonizationError: Error, Equatable, Sendable {
  case system(CInt)
}

extension DaemonizationError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .system(let code): "unable to daemonize server (\(code))"
    }
  }
}

internal enum DaemonizationOrder: Sendable {
  case before
  case after
}
