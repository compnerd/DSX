// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DSX {
  public enum Debuggee: Sendable {
    case attach(String)
    case launch(String, Array<String>)
  }

  public enum Notification: Sendable {
    case descriptor(CInt)
    case pipe(String)
    case file(String)
  }
}

internal typealias PortNotification = DSX.Notification
