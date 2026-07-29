// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBPacketError: Error, Equatable, Sendable {
  case checksum
  case malformed
}

internal enum GDBErrorCode {
  internal static let failure: UInt8 = 0x01
  internal static let invalid: UInt8 = 0x03
  internal static let unavailable: UInt8 = 0x04
  internal static let access: UInt8 = 0x0d
  internal static let terminal: UInt8 = 0x1c
  internal static let active: UInt8 = 0x35
  internal static let exception: UInt8 = 0x36
  internal static let busy: UInt8 = 0x37
  internal static let process: UInt8 = 0x44
  internal static let register: UInt8 = 0x45
  internal static let state: UInt8 = 0xff
}

internal enum GDBHandlerError: Error, Equatable, Sendable {
  case capacity
  case code(UInt8)
  case malformed
  case debuggee(Debuggee.Error)
  case unexpected
  case unsupported
}

internal enum GDBPacketDisposition: Equatable, Sendable {
  case close
  case none
  case reply
}

internal func translate<T>(_ body: @autoclosure () throws(Debuggee.Error) -> T)
    throws(GDBHandlerError) -> T where T: ~Copyable {
  do {
    return try body()
  } catch {
    throw .debuggee(error)
  }
}
