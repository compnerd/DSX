// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal struct LinuxDebugControl: ~Copyable, Sendable {
  internal var process: ProcessIdentifier?
  internal var attached = false
  internal var configured = false
  internal var status: CInt?
  internal var thread: pid_t?
  internal var deferred: Debuggee.Event?
  internal var breakpoints = ActiveBreakpoints()
  internal var requested = false
  internal var obsolete = false
  internal var threads = Dictionary<pid_t, LinuxThreadState>()
  internal var children = Set<pid_t>()
  internal var events = Array<Debuggee.Event>()
  internal var reader: CInt?
  internal var output: Debuggee.Output?
  internal var catches: Array<UInt64>?
}

internal struct LinuxThreadState: Sendable {
  internal var process: ProcessIdentifier
  /// A secondary wait result retained until stop or detach processing succeeds.
  internal var pending: CInt?
  internal var stopped = false
  internal var exiting = false
  internal var stepping = false
  internal var newborn = false
  internal var entry = false
  internal var signal: siginfo_t?
  internal var reported = false

  internal mutating func complete(_ signal: CInt, syscalls: Bool) {
    switch signal {
    case SIGTRAP | 0x80 where syscalls:
      entry.toggle()
    case SIGTRAP:
      stepping = false
    default:
      break
    }
  }
}

#endif
