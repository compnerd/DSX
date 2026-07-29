// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum FileFailure: Equatable, Sendable {
  case permission
  case missing
  case interrupted
  case io
  case descriptor
  case access
  case address
  case busy
  case exists
  case device
  case directory
  case folder
  case invalid
  case system
  case process
  case large
  case space
  case seek
  case readonly
  case unsupported
  case length
  case unknown
}
