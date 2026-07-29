// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum LogLevel: UInt8, Sendable {
  case trace
  case debug
  case info
  case notice
  case warning
  case error
  case critical
  case off

  internal var label: StaticString {
    switch self {
    case .trace: "trace"
    case .debug: "debug"
    case .info: "info"
    case .notice: "notice"
    case .warning: "warning"
    case .error: "error"
    case .critical: "critical"
    case .off: "off"
    }
  }

  internal var colour: StaticString {
    switch self {
    case .trace: "\u{001b}[90m"
    case .debug: "\u{001b}[36m"
    case .info: "\u{001b}[32m"
    case .notice: "\u{001b}[34m"
    case .warning: "\u{001b}[33m"
    case .error: "\u{001b}[31m"
    case .critical: "\u{001b}[1;31m"
    case .off: ""
    }
  }
}

internal enum LogColour: Sendable {
  case auto
  case always
  case never
}
