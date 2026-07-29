// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsPseudoConsoleProcess: @unchecked Sendable {
  internal let information: PROCESS_INFORMATION
  internal let reader: HANDLE
  internal let writer: HANDLE
  internal let console: HANDLE
}

internal enum WindowsPseudoConsole {
  internal static func enabled(_ config: borrowing Debuggee.Launch) -> Bool {
    guard case .none = config.input, case .none = config.output,
        case .none = config.error, let terminal = config.terminal else {
      return false
    }
    return terminal.columns > 0 && terminal.rows > 0
  }

  internal static func launch(_ application: inout Array<WCHAR>,
                              command: inout Array<WCHAR>,
                              environment: inout Array<WCHAR>,
                              directory working: inout Array<WCHAR>,
                              terminal: Debuggee.TerminalSize)
      throws(Debuggee.Error) -> WindowsPseudoConsoleProcess {
    guard terminal.columns <= Int16.max, terminal.rows <= Int16.max else {
      throw WindowsDebugControl.failure(ERROR_INVALID_PARAMETER)
    }
    var input: HANDLE?
    var writer: HANDLE?
    var reader: HANDLE?
    var output: HANDLE?
    guard CreatePipe(&input, &writer, nil, 0), let input, let writer else {
      let code = GetLastError()
      close(input)
      close(writer)
      throw WindowsDebugControl.failure(code)
    }
    guard CreatePipe(&reader, &output, nil, 0), let reader, let output else {
      let code = GetLastError()
      _ = CloseHandle(input)
      _ = CloseHandle(writer)
      close(reader)
      close(output)
      throw WindowsDebugControl.failure(code)
    }
    var console: HANDLE?
    let size = COORD(X: SHORT(terminal.columns), Y: SHORT(terminal.rows))
    let status = CreatePseudoConsole(size, input, output, 0, &console)
    _ = CloseHandle(input)
    _ = CloseHandle(output)
    guard status >= 0 else {
      _ = CloseHandle(writer)
      _ = CloseHandle(reader)
      throw WindowsPath.failure(status)
    }
    guard let console else {
      _ = CloseHandle(writer)
      _ = CloseHandle(reader)
      throw WindowsDebugControl.failure(ERROR_INVALID_PARAMETER)
    }
    var cleanup = true
    defer {
      if cleanup {
        _ = CloseHandle(writer)
        _ = CloseHandle(reader)
        ClosePseudoConsole(console)
      }
    }
    var startup = STARTUPINFOW()
    let flags = DEBUG_ONLY_THIS_PROCESS | CREATE_NEW_PROCESS_GROUP
              | CREATE_UNICODE_ENVIRONMENT
    let information =
        try WindowsProcess.create(&application, command: &command,
                                  environment: &environment,
                                  directory: &working, startup: &startup,
                                  console: console, flags: flags)
    cleanup = false
    return WindowsPseudoConsoleProcess(information: information, reader: reader,
                                       writer: writer, console: console)
  }

  private static func close(_ handle: HANDLE?) {
    if let handle {
      _ = CloseHandle(handle)
    }
  }
}
#endif
