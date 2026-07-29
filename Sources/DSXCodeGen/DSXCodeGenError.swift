// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum DSXCodeGenError:
    Error, Equatable, Sendable, CustomStringConvertible {
  case argument(String)
  case input(String)
  case output(String)
  case schema(String)

  internal var description: String {
    switch self {
    case .argument(let message), .schema(let message):
      message
    case .input(let path):
      "unable to read '\(path)'"
    case .output(let path):
      "unable to write '\(path)'"
    }
  }
}
