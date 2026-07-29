// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  internal mutating func launch(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    try config.validate()
    guard let executable = config.executable else {
      throw .process
    }
    var invocation = try WindowsCommand(executable,
                                        arguments: config.arguments.span,
                                        directory: config.directory,
                                        environment: config.environment.span)
    if WindowsPseudoConsole.enabled(config), let terminal = config.terminal {
      let created =
          try WindowsPseudoConsole.launch(&invocation, terminal: terminal)
      return try adopt(created)
    }
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    let capture = switch (config.output, config.error) {
    case (.some, .some): false
    default: true
    }
    var security = SECURITY_ATTRIBUTES()
    security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
    security.bInheritHandle = true
    var reader: HANDLE?
    var writer: HANDLE?
    var source: HANDLE?
    var sink: HANDLE?
    var transfer = true
    defer {
      if transfer {
        if let reader {
          _ = CloseHandle(reader)
        }
        if let writer {
          _ = CloseHandle(writer)
        }
        if let source {
          _ = CloseHandle(source)
        }
        if let sink {
          _ = CloseHandle(sink)
        }
      }
    }
    if capture {
      guard CreatePipe(&reader, &writer, &security, 0), let reader else {
        throw Debuggee.Error(process: GetLastError())
      }
      guard SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0) else {
        let code = GetLastError()
        throw Debuggee.Error(process: code)
      }
    }
    if case .none = config.input {
      guard CreatePipe(&source, &sink, &security, 0), let sink else {
        throw Debuggee.Error(process: GetLastError())
      }
      guard SetHandleInformation(sink, HANDLE_FLAG_INHERIT, 0) else {
        let code = GetLastError()
        throw Debuggee.Error(process: code)
      }
    }
    let input = if case .none = config.input, let source {
      WindowsRedirection.borrowed(source)
    } else {
      try WindowsRedirection(config.input, standard: STD_INPUT_HANDLE,
                             access: GENERIC_READ, creation: OPEN_EXISTING,
                             directory: config.directory, security: &security)
    }
    let output = if case .none = config.output, let writer {
      WindowsRedirection.borrowed(writer)
    } else {
      try WindowsRedirection(config.output, standard: STD_OUTPUT_HANDLE,
                             access: GENERIC_WRITE, creation: CREATE_ALWAYS,
                             directory: config.directory, security: &security)
    }
    let error = if case .none = config.error, let writer {
      WindowsRedirection.borrowed(writer)
    } else {
      try WindowsRedirection(config.error, standard: STD_ERROR_HANDLE,
                             access: GENERIC_WRITE, creation: CREATE_ALWAYS,
                             directory: config.directory, security: &security)
    }
    startup.dwFlags |= STARTF_USESTDHANDLES
    startup.hStdInput = input.value
    startup.hStdOutput = output.value
    startup.hStdError = error.value
    let flags = DEBUG_ONLY_THIS_PROCESS | CREATE_NEW_PROCESS_GROUP
              | CREATE_UNICODE_ENVIRONMENT
    let information = try invocation.create(&startup, flags: flags)
    let identifier = try adopt(information)
    if capture {
      if let writer {
        _ = CloseHandle(writer)
      }
      self.reader = reader
    }
    if let source {
      _ = CloseHandle(source)
    }
    self.writer = sink
    transfer = false
    return identifier
  }

  private mutating func adopt(_ created: WindowsPseudoConsoleProcess)
      throws(Debuggee.Error) -> ProcessIdentifier {
    var cleanup = true
    defer {
      if cleanup {
        _ = CloseHandle(created.reader)
        _ = CloseHandle(created.writer)
        ClosePseudoConsole(created.console)
      }
    }
    let information = created.information
    let identifier = try adopt(information)
    reader = created.reader
    writer = created.writer
    console = created.console
    cleanup = false
    return identifier
  }

  private mutating func adopt(_ information: PROCESS_INFORMATION)
      throws(Debuggee.Error) -> ProcessIdentifier {
    defer {
      _ = CloseHandle(information.hThread)
      _ = CloseHandle(information.hProcess)
    }
    guard DebugSetProcessKillOnExit(false) else {
      let code = GetLastError()
      _ = TerminateProcess(information.hProcess, 1)
      _ = WaitForSingleObject(information.hProcess, INFINITE)
      throw Debuggee.Error(process: code)
    }
    let identifier =
        ProcessIdentifier(rawValue: UInt64(information.dwProcessId))
    process = identifier
    return identifier
  }
}
#endif
