// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsProcess: ~Copyable {
  internal let process: ProcessIdentifier
  private var handle: HANDLE?
  private let reader: HANDLE

  internal init(_ executable: String, command: String,
                directory working: String?, errors: Bool, flags: DWORD,
                config: borrowing Debuggee.Launch = Debuggee.Launch(),
                capture: Bool = true) throws(Debuggee.Error) {
    var reader: HANDLE?
    var writer: HANDLE?
    var security = SECURITY_ATTRIBUTES()
    security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
    security.bInheritHandle = true
    guard CreatePipe(&reader, &writer, &security, 0),
        let reader, let writer else {
      throw WindowsProcess.failure(GetLastError())
    }
    var open = true
    defer {
      if open {
        _ = CloseHandle(reader)
        _ = CloseHandle(writer)
      }
    }
    guard SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0) else {
      throw WindowsProcess.failure(GetLastError())
    }

    var application = Array(executable.utf16) + [0]
    var command = Array(command.utf16) + [0]
    var directory = working.map { Array($0.utf16) + [0] } ?? []
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startup.dwFlags = STARTF_USESTDHANDLES
    let input = try WindowsProcess.redirect(config.input,
                                            standard: STD_INPUT_HANDLE,
                                            access: GENERIC_READ,
                                            creation: OPEN_EXISTING,
                                            directory: working,
                                            security: &security)
    let output = try WindowsProcess.redirect(config.output,
                                             standard: STD_OUTPUT_HANDLE,
                                             access: GENERIC_WRITE,
                                             creation: CREATE_ALWAYS,
                                             directory: working,
                                             security: &security)
    let error = try WindowsProcess.redirect(config.error,
                                            standard: STD_ERROR_HANDLE,
                                            access: GENERIC_WRITE,
                                            creation: CREATE_ALWAYS,
                                            directory: working,
                                            security: &security)
    startup.hStdInput = input.value
    startup.hStdOutput = capture && config.output == nil ? writer : output.value
    startup.hStdError = errors && config.error == nil ? writer : error.value
    var environment = try WindowsProcess.environment(config.environment.span)
    let flags = flags | CREATE_UNICODE_ENVIRONMENT
    let information =
        try WindowsProcess.create(&application, command: &command,
                                  environment: &environment,
                                  directory: &directory, startup: &startup,
                                  flags: flags)
    _ = CloseHandle(information.hThread)
    _ = CloseHandle(writer)
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

  internal borrowing func byte() throws(Debuggee.Error) -> UInt8 {
    var byte: UInt8 = 0
    var count: DWORD = 0
    guard ReadFile(reader, &byte, 1, &count, nil) else {
      let code = GetLastError()
      guard code == ERROR_BROKEN_PIPE else {
        throw WindowsProcess.failure(code)
      }
      throw termination()
    }
    guard count == 1 else {
      throw termination()
    }
    return byte
  }

  internal borrowing func prepare() throws(Debuggee.Error) {
  }

  internal borrowing func status(_ timeout: Int32) throws(Debuggee.Error)
      -> Debuggee.Exit? {
    let result = WaitForSingleObject(handle, DWORD(timeout))
    switch result {
    case WAIT_OBJECT_0:
      var code: DWORD = 0
      guard GetExitCodeProcess(handle, &code) else {
        throw WindowsProcess.failure(GetLastError())
      }
      return .exited(CInt(bitPattern: code))
    case WAIT_TIMEOUT:
      return nil
    default:
      throw WindowsProcess.failure(GetLastError())
    }
  }

  internal borrowing func terminate() throws(Debuggee.Error) {
    guard TerminateProcess(handle, 1) else {
      throw WindowsProcess.failure(GetLastError())
    }
    _ = WaitForSingleObject(handle, INFINITE)
  }

  internal static func command(_ arguments: borrowing Span<String>) -> String {
    var command = ""
    for index in 0 ..< arguments.count {
      if index > 0 {
        command.append(" ")
      }
      command.append(quote(arguments[index]))
    }
    return command
  }

  internal static func command(_ executable: borrowing String,
                               arguments: borrowing Span<String>) -> String {
    var command = quote(executable)
    for index in 0 ..< arguments.count {
      command.append(" ")
      command.append(quote(arguments[index]))
    }
    return command
  }

  @inline(never)
  internal static func quote(_ argument: borrowing String) -> String {
    var argument = copy argument
    return argument.withUTF8 { bytes in
      let quoted = bytes.contains {
        $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") ||
            $0 == UInt8(ascii: "\"")
      }
      guard bytes.isEmpty || quoted else {
        return String(decoding: bytes, as: UTF8.self)
      }
      var result = [UInt8(ascii: "\"")]
      var slashes = 0
      for byte in bytes {
        if byte == UInt8(ascii: "\\") {
          slashes += 1
          continue
        }
        let count = byte == UInt8(ascii: "\"") ? slashes * 2 + 1 : slashes
        for _ in 0 ..< count {
          result.append(UInt8(ascii: "\\"))
        }
        result.append(byte)
        slashes = 0
      }
      for _ in 0 ..< (slashes * 2) {
        result.append(UInt8(ascii: "\\"))
      }
      result.append(UInt8(ascii: "\""))
      return String(decoding: result, as: UTF8.self)
    }
  }

  internal static func failure(_ code: DWORD) -> Debuggee.Error {
    WindowsError.debuggee(code, invalid: .process)
  }

  private borrowing func termination() -> Debuggee.Error {
    var code: DWORD = 0
    guard GetExitCodeProcess(handle, &code) else {
      return WindowsProcess.failure(GetLastError())
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
        throw WindowsProcess.failure(code)
      }
      return 0
    }
    guard available > 0 else {
      return 0
    }
    var count: DWORD = 0
    let capacity = min(DWORD(clamping: buffer.count), available)
    guard ReadFile(reader, buffer.baseAddress, capacity, &count, nil) else {
      throw WindowsProcess.failure(GetLastError())
    }
    return Int(count)
  }
}
#endif
