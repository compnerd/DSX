// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal typealias Continuations = Span<Continuation>

  internal struct Continuation: Equatable, Sendable {
    internal enum Operation: Equatable, Sendable {
      case resume
      case step
      case stop
    }

    internal enum Delivery: Equatable, Sendable {
      case thread
      case process
    }

    internal let selection: Thread.Selection
    internal let operation: Operation
    internal let signal: CInt?
    internal let address: Address?
    internal let delivery: Delivery

    internal init(selection: Thread.Selection, operation: Operation,
                  signal: CInt? = nil, address: Address? = nil,
                  delivery: Delivery = .thread) {
      self.selection = selection
      self.operation = operation
      self.signal = signal
      self.address = address
      self.delivery = delivery
    }

  }
}
