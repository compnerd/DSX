// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Thread: Sendable {
    internal typealias IDs = Span<ProcessThreadIdentifier>

    internal enum Selection: Equatable, Sendable {
      case all
      case any
      case process(ProcessIdentifier)
      case thread(ProcessThreadIdentifier)

      internal func applies(to process: ProcessIdentifier) -> Bool {
        switch self {
        case .all, .any: true
        case .process(let candidate): candidate == process
        case .thread(let candidate): candidate.process == process
        }
      }
    }

    internal enum State: Sendable {
      case running
      case stepping
      case stopped(Stop)
      case terminated
    }

    internal struct Info: Sendable {
      internal let thread: ProcessThreadIdentifier
      internal let name: String?
      internal let core: Int?
      internal let queue: UInt64?

      internal init(thread: ProcessThreadIdentifier,
                    name: consuming String? = nil, core: Int? = nil,
                    queue: UInt64? = nil) {
        self.thread = thread
        self.name = consume name
        self.core = core
        self.queue = queue
      }
    }

    internal struct Context: Sendable {
      internal let pthread: UInt64?
      internal let storage: UInt64?
      internal let queue: UInt64?
    }

    internal struct Layout: Sendable {
      internal let thread: ThreadIdentifier
      internal let address: UInt64
      internal let base: UInt64
      internal let size: UInt64
    }

    internal let identifier: ProcessThreadIdentifier
    internal var state: State

    internal init(identifier: ProcessThreadIdentifier,
                  state: State = .running) {
      self.identifier = identifier
      self.state = state
    }
  }
}
