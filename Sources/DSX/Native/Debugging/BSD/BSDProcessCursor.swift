// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
internal struct BSDProcessCursor: ~Copyable, Sendable {
  private let identifiers: Array<ProcessIdentifier>
  private var index: Int

  internal init() throws(Debuggee.Error) {
    var identifiers = try ProcessIdentifier.snapshot()
    identifiers.order { lhs, rhs in
      lhs.rawValue < rhs.rawValue
    }
    self.identifiers = identifiers
    index = 0
  }

  internal mutating func next() throws(Debuggee.Error)
      -> Debuggee.Process.Info? {
    guard index < identifiers.count else {
      return nil
    }
    let process = identifiers[index]
    index += 1
    return try process.info
  }
}
#endif
