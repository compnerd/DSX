// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct ExceptionMask: OptionSet, Sendable {
    internal let rawValue: UInt32

    internal init(rawValue: UInt32) {
      self.rawValue = rawValue
    }

    internal static let access = ExceptionMask(rawValue: 1 << 1)
    internal static let instruction = ExceptionMask(rawValue: 1 << 2)
    internal static let arithmetic = ExceptionMask(rawValue: 1 << 3)
    internal static let syscall = ExceptionMask(rawValue: 1 << 7)
    internal static let resource = ExceptionMask(rawValue: 1 << 11)
    internal static let guarded = ExceptionMask(rawValue: 1 << 12)
  }

  internal enum Access: Equatable, Sendable {
    case execute
    case read
    case readwrite
    case write
  }

  internal enum StopReason: Equatable, Sendable {
    case breakpoint
    case create
    case executed
    case exception(UInt64)
    case fork
    case interrupt
    case library
    case signal(CInt)
    case spawn
    case syscall(UInt64, Bool)
    case trace
    case vfork
    case vforkdone
    case watchpoint(Access, Address)
  }

  internal enum ExceptionChance: Equatable, Sendable {
    case first
    case second
  }

  internal enum ExceptionDomain: Equatable, Sendable {
    case mach
    case posix
    case windows
  }

  internal struct Fault: Sendable {
    internal let address: Address
    internal let code: UInt64?
    internal let data: ExceptionData?
    internal let domain: ExceptionDomain

    internal init(address: Address, code: UInt64? = nil,
                  data: consuming ExceptionData? = nil,
                  domain: ExceptionDomain) {
      self.address = address
      self.code = code
      self.data = consume data
      self.domain = domain
    }
  }

  internal struct ExceptionData: Sendable {
    private var values: InlineArray<15, UInt64>
    internal let count: Int

    internal init(count: Int, value: (Int) -> UInt64) {
      self.count = min(max(count, 0), 15)
      values = InlineArray<15, UInt64> { index in
        index < count ? value(index) : 0
      }
    }

    internal subscript(index: Int) -> UInt64 {
      values[index]
    }
  }

  internal struct Stop: Sendable {
    internal let thread: ProcessThreadIdentifier
    internal let reason: StopReason
    internal let core: Int?
    internal let fault: Fault?
    internal let breakpoint: BreakpointIdentifier?
    internal let child: ProcessThreadIdentifier?
    internal let snapshot: UInt64?
    internal let chance: ExceptionChance?

    internal init(thread: ProcessThreadIdentifier, reason: StopReason,
                  core: Int? = nil, fault: Fault? = nil,
                  breakpoint: BreakpointIdentifier? = nil,
                  child: ProcessThreadIdentifier? = nil,
                  snapshot: UInt64? = nil, chance: ExceptionChance? = nil) {
      self.thread = thread
      self.reason = reason
      self.core = core
      self.fault = fault
      self.breakpoint = breakpoint
      self.child = child
      self.snapshot = snapshot
      self.chance = chance
    }
  }

  internal enum Exit: Equatable, Sendable {
    case exited(CInt)
    case signalled(CInt)

    internal var code: CInt {
      switch self {
      case .exited(let code), .signalled(let code): code
      }
    }
  }

  internal enum ProgramStatus: Equatable, Sendable {
    case completed(Exit)
    case timeout
  }

  internal struct Fork: Sendable {
    internal let parent: ProcessThreadIdentifier
    internal let child: ProcessThreadIdentifier
    internal let vfork: Bool

    internal init(parent: ProcessThreadIdentifier,
                  child: ProcessThreadIdentifier, vfork: Bool) {
      self.parent = parent
      self.child = child
      self.vfork = vfork
    }
  }

  internal enum ImageAction: Equatable, Sendable {
    case load
    case unload
  }

  internal struct ImageEvent: Sendable {
    internal let process: ProcessIdentifier
    internal let path: String
    internal let address: Address
    internal let action: ImageAction

    internal init(process: ProcessIdentifier, path: consuming String,
                  address: Address, action: ImageAction) {
      self.process = process
      self.path = consume path
      self.address = address
      self.action = action
    }
  }

  internal enum Event: Sendable {
    case executed(ProcessThreadIdentifier)
    case exited(ProcessIdentifier, Exit)
    case forked(Fork)
    case image(ImageEvent)
    case output(ProcessIdentifier)
    case started(ProcessThreadIdentifier)
    case stopped(Stop)
    case terminated(ProcessThreadIdentifier, CInt)

    internal var completion: Bool {
      switch self {
      case .executed, .exited, .forked, .stopped:
        true
      case .image, .output, .started, .terminated:
        false
      }
    }

    internal var lifecycle: Bool {
      switch self {
      case .started, .terminated:
        true
      case .executed, .exited, .forked, .image, .output, .stopped:
        false
      }
    }

    internal var process: ProcessIdentifier {
      switch self {
      case .executed(let thread), .started(let thread),
          .terminated(let thread, _):
        thread.process
      case .exited(let process, _), .output(let process):
        process
      case .forked(let fork):
        fork.parent.process
      case .image(let image):
        image.process
      case .stopped(let stop):
        stop.thread.process
      }
    }

    internal var exited: Bool {
      if case .exited = self {
        true
      } else {
        false
      }
    }

    internal var refreshable: Bool {
      switch self {
      case .executed, .forked, .started, .stopped:
        true
      case .exited, .image, .output, .terminated:
        false
      }
    }
  }
}
