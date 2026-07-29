// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import DSX

extension DSX.Connection {
  internal static func parse(_ value: String, reverse: Bool = false)
      throws(DSX.Error) -> DSX.Connection {
    switch value {
    case let value where value.hasPrefix("fd://"):
      try handle(value.dropFirst(5))
    case let value where value.hasPrefix("device://") ||
        value.hasPrefix("serial://"):
      try location(value.dropFirst(9), pipe: false)
    case let value where value.hasPrefix("pipe://"):
      try location(value.dropFirst(7), pipe: true)
    case let value where value.hasPrefix("unix://"):
      try local(value.dropFirst(7), reverse: reverse)
    default:
      try socket(value[...], reverse: reverse)
    }
  }
}

private func decimal(_ value: Substring, limit: UInt32) -> UInt32? {
  guard !value.isEmpty else {
    return nil
  }
  var first = true
  var negative = false
  var parsed = false
  var result: UInt32 = 0
  for byte in value.utf8 {
    if first {
      first = false
      switch byte {
      case UInt8(ascii: "+"):
        continue
      case UInt8(ascii: "-"):
        negative = true
        continue
      default:
        break
      }
    }
    guard UInt8(ascii: "0") ... UInt8(ascii: "9") ~= byte else {
      return nil
    }
    parsed = true
    let digit = UInt32(byte - UInt8(ascii: "0"))
    guard result <= (limit - digit) / 10 else {
      return nil
    }
    result = result * 10 + digit
  }
  guard parsed else {
    return nil
  }
  if negative {
    guard result == 0 else {
      return nil
    }
  }
  return result
}

private func handle(_ value: Substring) throws(DSX.Error) -> DSX.Connection {
  guard let value = decimal(value, limit: UInt32(CInt.max)) else {
    throw .failure("invalid file descriptor")
  }
  return .descriptor(CInt(value))
}

private func location(_ value: Substring, pipe: Bool) throws(DSX.Error)
    -> DSX.Connection {
  guard !value.isEmpty else {
    throw .failure("invalid connection location")
  }
  return if pipe {
    .pipe(String(value))
  } else {
    .device(String(value))
  }
}

private func socket(_ value: Substring, reverse: Bool) throws(DSX.Error)
    -> DSX.Connection {
  guard let separator = value.lastIndex(of: ":") else {
    throw .failure("invalid network address")
  }
  let service = value[value.index(after: separator)...]
  guard let port = decimal(service, limit: UInt32(UInt16.max)) else {
    throw .failure("invalid network port")
  }
  let address = value[..<separator]
  let host: String? = switch (address.first, address.last) {
  case ("[", "]") where address.count > 2:
    String(address.dropFirst().dropLast())
  case ("[", _), (_, "]"):
    throw .failure("invalid network address")
  case _ where address.contains(":"):
    throw .failure("invalid network address")
  default:
    address.isEmpty || address == "*" ? nil : String(address)
  }
  return .network(host, port: UInt16(port), reverse: reverse)
}

private func local(_ value: Substring, reverse: Bool) throws(DSX.Error)
    -> DSX.Connection {
  guard !value.isEmpty else {
    throw .failure("invalid connection location")
  }
  return .unix(String(value), reverse: reverse)
}
