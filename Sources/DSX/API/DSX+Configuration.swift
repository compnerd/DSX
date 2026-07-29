// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DSX {
  /// Notification ownership for in-process Linux and Android debug sessions.
  /// Platform servers launch independent children which own their signals.
  public enum Events: Sendable {
    /// Does not change the application's signal handling.
    case polling
    /// Consumes SIGCHLD on the calling thread for the duration of run().
    /// Other threads must block SIGCHLD, and no other consumer may reap
    /// DSX's tracees. Run and signal-mask restoration stay on this thread.
    /// SIGCHLD must retain its default disposition without SA_NOCLDSTOP or
    /// SA_NOCLDWAIT; DSX does not change the process-wide disposition.
    /// Other platforms retain their existing native event handling.
    case signals
    /// Borrows a dedicated, readable, nonblocking notification descriptor.
    /// DSX drains its bytes; the host must notify it of tracee state changes
    /// without reaping those states. Keep it open throughout run().
    /// Supported on Linux and Android; other platforms reject this option.
    case descriptor(CInt)
  }

  public enum Debuggee: Sendable {
    case attach(String)
    case launch(String, Array<String>)
  }

  public enum Notification: Sendable {
    case descriptor(CInt)
    case pipe(String)
    case file(String)
  }

  public enum Configuration: Sendable {
    case gdb(Connection, debuggee: Debuggee?, notification: Notification?)
    case lldb(Connection, debuggee: Debuggee?, notification: Notification?)
    case platform(Connection, multiple: Bool, port: UInt16?,
                  executable: String?, notification: Notification?)
  }
}

internal typealias PortNotification = DSX.Notification
