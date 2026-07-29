// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal struct LinuxDebugControl: ~Copyable, Sendable {
  internal var process: ProcessIdentifier?
  internal var attached = false
  internal var configured = false
  internal var status: CInt?
  internal var thread: pid_t?
  internal var breakpoints = ActiveBreakpoints()
  internal var stepping = Set<pid_t>()
  internal var requested = false
  internal var obsolete = false
  internal var stopped = Set<pid_t>()
  internal var owners = Dictionary<pid_t, ProcessIdentifier>()
  internal var newborn = Set<pid_t>()
  internal var children = Set<pid_t>()
  internal var events = Array<Debuggee.Event>()
  internal var reader: CInt?
  internal var output: Debuggee.Output?
  internal var catches: Array<UInt64>?
  internal var entries = Set<pid_t>()
}

#endif
