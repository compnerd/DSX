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
    case let .argument(message), let .schema(message): message
    case let .input(path): "unable to read '\(path)'"
    case let .output(path): "unable to write '\(path)'"
    }
  }
}
