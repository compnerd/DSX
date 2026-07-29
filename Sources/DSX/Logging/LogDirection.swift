// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum LogDirection: Sendable {
  case incoming
  case outgoing

  internal var symbol: StaticString {
    switch self {
    case .incoming: "←"
    case .outgoing: "→"
    }
  }

  internal var colour: StaticString {
    switch self {
    case .incoming: "\u{001b}[34m"
    case .outgoing: "\u{001b}[35m"
    }
  }
}
