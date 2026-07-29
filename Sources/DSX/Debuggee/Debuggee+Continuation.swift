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

    internal let selection: Thread.Selection
    internal let operation: Operation
    internal let signal: CInt?
    internal let address: Address?

    internal init(selection: Thread.Selection, operation: Operation,
                  signal: CInt? = nil, address: Address? = nil) {
      self.selection = selection
      self.operation = operation
      self.signal = signal
      self.address = address
    }

    /// Resolves overlapping actions using the GDB remote precedence rules.
    ///
    /// A thread-specific action overrides a process action, which overrides the
    /// default action. The representation borrows the packet's action span and
    /// performs no allocation.
    internal enum Plan {
      internal static func select(_ thread: ProcessThreadIdentifier,
                                  actions: borrowing Continuations)
          -> Continuation? {
        selection(thread.process, thread: thread, actions: actions).action
      }

      internal static func resolve(_ thread: ProcessThreadIdentifier,
                                   actions: borrowing Continuations)
          throws(Error) -> Continuation? {
        let selection =
            selection(thread.process, thread: thread, actions: actions)
        if selection.conflict {
          throw .state
        }
        return selection.action
      }

      internal static func fallback(_ process: ProcessIdentifier,
                                    actions: borrowing Continuations)
          throws(Error) -> Continuation? {
        let selection = selection(process, thread: nil, actions: actions)
        if selection.conflict {
          throw .state
        }
        return selection.action
      }

      private static func selection(_ process: ProcessIdentifier,
                                    thread: ProcessThreadIdentifier?,
                                    actions: borrowing Continuations)
          -> (action: Continuation?, conflict: Bool) {
        var selected: Continuation?
        var priority = 0
        var conflict = false
        for index in 0 ..< actions.count {
          let action = actions[index]
          let candidate = switch action.selection {
          case .thread(let identifier):
            identifier == thread ? 3 : 0
          case .process(let identifier):
            identifier == process ? 2 : 0
          case .all, .any: 1
          }
          guard candidate > 0 else {
            continue
          }
          if candidate > priority {
            selected = action
            priority = candidate
            continue
          }
          if candidate == priority, selected != action {
            conflict = true
          }
        }
        return (selected, conflict)
      }
    }
  }
}
