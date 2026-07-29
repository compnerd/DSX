// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DSX {
  public enum Connection: Sendable {
    case descriptor(CInt)
    case device(String)
    case pipe(String)
    case network(String?, port: UInt16, reverse: Bool)
    case unix(String, reverse: Bool)
  }
}

internal typealias Connection = DSX.Connection
