// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum ServerError: Error {
  case daemon(DaemonizationError)
  case session
  case state
  case transport(TransportError)
  case debuggee(Debuggee.Error)
}

extension ServerError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case let .daemon(error): error.description
    case .session: "debug protocol failure"
    case .state: "debug session is unavailable"
    case let .transport(error): error.description
    case let .debuggee(error): error.description
    }
  }
}
