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
    case .accept(let code): "socket accept failed (\(code))"
    case .address(let code): "address resolution failed (\(code))"
    case .bind(let code): "socket bind failed (\(code))"
    case .connect(let code): "socket connection failed (\(code))"
    case .create(let code): "socket creation failed (\(code))"
    case .descriptor(let code): "invalid stream descriptor (\(code))"
    case .listen(let code): "socket listen failed (\(code))"
    case .name(let code): "socket name query failed (\(code))"
    case .notification:
      "port notification requires a listening network endpoint"
    case .open(let code): "stream open failed (\(code))"
    case .option(let code): "socket option failed (\(code))"
    case .output(let code): "listener announcement failed (\(code))"
    case .path: "invalid local socket address"
    case .read(let code): "transport read failed (\(code))"
    case .type(let code): "unexpected stream type (\(code))"
    case .write(let code): "transport write failed (\(code))"
    }
  }
}
