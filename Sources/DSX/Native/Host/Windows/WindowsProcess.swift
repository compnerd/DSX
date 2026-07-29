// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsProcess: ~Copyable {
  internal let process: ProcessIdentifier
  private var handle: HANDLE?
  private let reader: HANDLE

  internal init(_ executable: String, command: String, directory: String?,
                errors: Bool, flags: DWORD,
                config: borrowing Debuggee.Launch = Debuggee.Launch(),
                capture: Bool = true) throws(Debuggee.Error) {
    try config.validate()
    var reader: HANDLE?
    var writer: HANDLE?
    var security = SECURITY_ATTRIBUTES()
    security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
    security.bInheritHandle = true
    guard CreatePipe(&reader, &writer, &security, 0),
        let reader, let writer else {
      throw Debuggee.Error(process: GetLastError())
    }
    defer { _ = CloseHandle(writer) }
    var open = true
    defer {
      if open {
        _ = CloseHandle(reader)
      }
    }
    guard SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0) else {
      throw Debuggee.Error(process: GetLastError())
    }

    var invocation = try WindowsCommand(executable, command: command,
                                        directory: directory,
                                        environment: config.environment.span)
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startup.dwFlags = STARTF_USESTDHANDLES
    let input = try WindowsRedirection(config.input, standard: STD_INPUT_HANDLE,
                                       access: GENERIC_READ,
                                       creation: OPEN_EXISTING,
                                       directory: directory,
                                       security: &security)
    let output = if capture, config.output == nil {
      WindowsRedirection.borrowed(writer)
    } else {
      try WindowsRedirection(config.output, standard: STD_OUTPUT_HANDLE,
                             access: GENERIC_WRITE, creation: CREATE_ALWAYS,
                             directory: directory, security: &security)
    }
    let error = if errors, config.error == nil {
      WindowsRedirection.borrowed(writer)
    } else {
      try WindowsRedirection(config.error, standard: STD_ERROR_HANDLE,
                             access: GENERIC_WRITE, creation: CREATE_ALWAYS,
                             directory: directory, security: &security)
    }
    startup.hStdInput = input.value
    startup.hStdOutput = output.value
    startup.hStdError = error.value
    let flags = flags | CREATE_UNICODE_ENVIRONMENT
    let information = try invocation.create(&startup, flags: flags)
    _ = CloseHandle(information.hThread)
    open = false
    process = ProcessIdentifier(rawValue: UInt64(information.dwProcessId))
    handle = information.hProcess
    self.reader = reader
  }

  deinit {
    _ = CloseHandle(reader)
    if let handle {
      _ = CloseHandle(handle)
    }
  }

  internal consuming func monitor() -> WaitHandle? {
    let monitor = handle.map { WaitHandle($0) }
    handle = nil
    return monitor
  }

  internal borrowing func byte(timeout: Int32) throws(Debuggee.Error)
      -> UInt8? {
    var available: DWORD = 0
    guard PeekNamedPipe(reader, nil, 0, nil, &available, nil) else {
      let code = GetLastError()
      guard code == ERROR_BROKEN_PIPE else {
        throw Debuggee.Error(process: code)
      }
      throw termination()
    }
    if available == 0 {
      Sleep(DWORD(clamping: timeout))
      return nil
    }
    var byte: UInt8 = 0
    var count: DWORD = 0
    guard ReadFile(reader, &byte, 1, &count, nil) else {
      let code = GetLastError()
      guard code == ERROR_BROKEN_PIPE else {
        throw Debuggee.Error(process: code)
      }
      throw termination()
    }
    guard count == 1 else {
      throw termination()
    }
    return byte
  }

  internal borrowing func status(timeout: Int32) throws(Debuggee.Error)
      -> Debuggee.Exit? {
    let result = WaitForSingleObject(handle, DWORD(timeout))
    switch result {
    case WAIT_OBJECT_0:
      var code: DWORD = 0
      guard GetExitCodeProcess(handle, &code) else {
        throw Debuggee.Error(process: GetLastError())
      }
      return .exited(CInt(bitPattern: code))
    case WAIT_TIMEOUT:
      return nil
    default:
      throw Debuggee.Error(process: GetLastError())
    }
  }

  internal borrowing func terminate() throws(Debuggee.Error) {
    guard TerminateProcess(handle, 1) else {
      throw Debuggee.Error(process: GetLastError())
    }
    _ = WaitForSingleObject(handle, INFINITE)
  }

  private borrowing func termination() -> Debuggee.Error {
    var code: DWORD = 0
    guard GetExitCodeProcess(handle, &code) else {
      return Debuggee.Error(process: GetLastError())
    }
    if code == STILL_ACTIVE {
      return .state
    }
    return .exited(CInt(bitPattern: code))
  }

  internal borrowing func read(_ buffer: UnsafeMutableBufferPointer<UInt8>)
      throws(Debuggee.Error) -> Int {
    var available: DWORD = 0
    guard PeekNamedPipe(reader, nil, 0, nil, &available, nil) else {
      let code = GetLastError()
      guard code == ERROR_BROKEN_PIPE else {
        throw Debuggee.Error(process: code)
      }
      return 0
    }
    guard available > 0 else {
      return 0
    }
    var count: DWORD = 0
    let capacity = min(DWORD(clamping: buffer.count), available)
    guard ReadFile(reader, buffer.baseAddress, capacity, &count, nil) else {
      throw Debuggee.Error(process: GetLastError())
    }
    return Int(count)
  }
}
#endif
