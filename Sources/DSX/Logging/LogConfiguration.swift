// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum LogConfigurationError: Error, Equatable, Sendable {
  case channel(String)
  case destination(CInt)
  case syntax
}

extension LogConfigurationError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .channel(let name): "unknown log channel or level '\(name)'"
    case .destination(let code): "unable to open log destination (\(code))"
    case .syntax: "log channel specification is empty"
    }
  }
}

internal struct LogConfiguration {
  internal let channels: UInt64
  internal let level: LogLevel

  internal static func parse(_ value: String?) throws(LogConfigurationError)
      -> LogConfiguration {
    guard let value else {
      return LogConfiguration(channels: LogChannel.all, level: .info)
    }
    guard !value.isEmpty else {
      throw .syntax
    }
    var selection = LogSelection()
    var start = value.startIndex
    var index = start
    while true {
      let end = index == value.endIndex
      let separator = if end { false } else {
        value[index] == ":" || value[index] == "," || value[index].isWhitespace
      }
      if end || separator {
        if start < index {
          try selection.apply(value[start ..< index])
        }
        if end {
          break
        }
        let colon = value[index] == ":"
        value.formIndex(after: &index)
        start = index
        if colon {
          selection.first = true
        }
      } else {
        value.formIndex(after: &index)
      }
    }
    return selection.configuration
  }
}

private struct LogSelection {
  fileprivate var channels: UInt64 = 0
  fileprivate var level = LogLevel.trace
  fileprivate var unrestricted = false
  fileprivate var first = true

  fileprivate var configuration: LogConfiguration {
    let selection = if unrestricted || channels == 0 {
      LogChannel.all
    } else {
      channels
    }
    return LogConfiguration(channels: selection, level: level)
  }

  fileprivate mutating func apply(_ token: Substring)
      throws(LogConfigurationError) {
    if first, namespace(token) {
      first = false
      return
    }
    first = false
    if let channel = channel(token) {
      channels |= channel.bit
      return
    }
    switch token {
    case "all": unrestricted = true
    case "trace": level = .trace
    case "debug": level = .debug
    case "info": level = .info
    case "notice": level = .notice
    case "warning", "warn": level = .warning
    case "error": level = .error
    case "critical", "fatal": level = .critical
    case "off", "none": level = .off
    default: throw .channel(String(token))
    }
  }
}

private func namespace(_ value: Substring) -> Bool {
  switch value {
  case "gdb-remote", "lldb":
    true
  default:
    false
  }
}

private func channel(_ value: Substring) -> LogChannel? {
  switch value {
  case "network": .network
  case "packet": .packet
  case "parser": .parser
  case "process": .process
  case "protocol": .remote
  case "system": .system
  case "transport": .transport
  case "communication": .transport
  case "connection": .network
  case "events", "thread", "threads": .process
  case "packets": .packet
  case "platform": .system
  case "remote": .remote
  default: nil
  }
}
