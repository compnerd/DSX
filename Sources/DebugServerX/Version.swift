// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import DSXArguments

internal struct Version {
  internal init() {
  }

  internal static func parse(_ values: borrowing Array<String>)
      throws(ArgumentError) -> Version {
    switch values.first {
    case nil: Version()
    case "-h"?, "--help"?: throw .help
    case let value?: throw .failure("Unexpected argument '\(value)'")
    }
  }

  internal mutating func run() {
    output("DebugServerX version 0.0.0")
  }
}
