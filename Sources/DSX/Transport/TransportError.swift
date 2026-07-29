// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum TransportError: Error, Equatable, Sendable {
  case accept(CInt)
  case address(CInt)
  case bind(CInt)
  case connect(CInt)
  case create(CInt)
  case descriptor(CInt)
  case listen(CInt)
  case name(CInt)
  case notification
  case open(CInt)
  case option(CInt)
  case output(CInt)
  case path
  case read(CInt)
  case type(CInt)
  case write(CInt)
}

extension TransportError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case let .accept(code): "socket accept failed (\(code))"
    case let .address(code): "address resolution failed (\(code))"
    case let .bind(code): "socket bind failed (\(code))"
    case let .connect(code): "socket connection failed (\(code))"
    case let .create(code): "socket creation failed (\(code))"
    case let .descriptor(code): "invalid stream descriptor (\(code))"
    case let .listen(code): "socket listen failed (\(code))"
    case let .name(code): "socket name query failed (\(code))"
    case .notification:
      "port notification requires a listening network endpoint"
    case let .open(code): "stream open failed (\(code))"
    case let .option(code): "socket option failed (\(code))"
    case let .output(code): "listener announcement failed (\(code))"
    case .path: "invalid local socket address"
    case let .read(code): "transport read failed (\(code))"
    case let .type(code): "unexpected stream type (\(code))"
    case let .write(code): "transport write failed (\(code))"
    }
  }
}
