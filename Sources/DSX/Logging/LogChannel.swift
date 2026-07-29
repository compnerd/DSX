// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum LogChannel: Equatable, Sendable {
  case network
  case packet
  case parser
  case process
  case remote
  case system
  case transport

  internal init?(rawValue: String) {
    switch rawValue {
    case "network": self = .network
    case "packet": self = .packet
    case "parser": self = .parser
    case "process": self = .process
    case "protocol": self = .remote
    case "system": self = .system
    case "transport": self = .transport
    default: return nil
    }
  }

  internal var rawValue: String {
    switch self {
    case .network: "network"
    case .packet: "packet"
    case .parser: "parser"
    case .process: "process"
    case .remote: "protocol"
    case .system: "system"
    case .transport: "transport"
    }
  }

  internal var bit: UInt64 {
    switch self {
    case .network: 0x01
    case .packet: 0x02
    case .parser: 0x04
    case .process: 0x08
    case .remote: 0x10
    case .system: 0x20
    case .transport: 0x40
    }
  }

  internal var label: StaticString {
    switch self {
    case .network: "network"
    case .packet: "packet"
    case .parser: "parser"
    case .process: "process"
    case .remote: "protocol"
    case .system: "system"
    case .transport: "transport"
    }
  }

  internal static var all: UInt64 {
    0x7f
  }
}
