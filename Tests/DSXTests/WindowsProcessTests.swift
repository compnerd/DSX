// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsProcessTests {
  @Test(arguments: 0 ..< 3)
  internal func validation(_ field: Int) throws {
    let name = "dsx-preflight-\(GetCurrentProcessId())-\(field)"
    let directory = try WindowsEnvironment["TEMP"]
    let path = try NativeFileSystem.resolve(name, directory: directory)
    let bytes = Array("retained".utf8)
    do {
      let options: FileOptions = [.create, .exclusive, .write]
      let handle =
          try NativeFileSystem.open(path, options: options, mode: 0o600)
      defer { try? NativeFileSystem.close(handle) }
      let count =
          try NativeFileSystem.write(handle, offset: 0, bytes: bytes.span)
      #expect(count == bytes.count)
    }
    defer {
      try? NativeFileSystem.remove(path)
    }
    var config = Debuggee.Launch(output: field == 1 ? path + "\0suffix" : path)
    if field == 2 {
      config.environment = [Debuggee.Environment(name: "KEY", value: "x\0y")]
    }
    let command = field == 0 ? "missing\0suffix" : "missing"
    let failure: Debuggee.Error = field == 2 ? .state : .process
    #expect(throws: failure) {
      _ = try WindowsProcess("missing", command: command, directory: nil,
                             errors: true, flags: CREATE_NO_WINDOW,
                             config: config)
    }
    #expect(try NativeFileSystem.size(path) == UInt64(bytes.count))
  }

  @Test
  internal func inheritance() throws {
    var security = SECURITY_ATTRIBUTES()
    security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
    security.bInheritHandle = true
    let event = try #require(CreateEventW(&security, true, false, nil))
    defer {
      _ = CloseHandle(event)
    }
    let executable = try WindowsEnvironment["COMSPEC"]
    let arguments = ["/d", "/c", "exit", "0"]
    let command = String(command: executable, arguments: arguments.span)
    let flags = DWORD(WinSDK.CREATE_SUSPENDED) | CREATE_NO_WINDOW
    let child = try WindowsProcess(executable, command: command, directory: nil,
                                   errors: true, flags: flags)
    defer {
      try? child.terminate()
    }
    let process = try child.process.native
    let access = DWORD(PROCESS_DUP_HANDLE)
#if arch(i386)
    let raw = DSX::OpenProcess(access, false, process)
#else
    let raw = WinSDK.OpenProcess(access, false, process)
#endif
    let handle = try #require(raw)
    defer {
      _ = CloseHandle(handle)
    }
    var duplicate: HANDLE?
    if DuplicateHandle(handle, event, GetCurrentProcess(), &duplicate, 0, false,
                       DWORD(DUPLICATE_SAME_ACCESS)), let duplicate {
      defer {
        _ = CloseHandle(duplicate)
      }
      #expect(CompareObjectHandles(event, duplicate) == false)
    } else {
      #expect(GetLastError() == ERROR_INVALID_HANDLE)
    }
  }

  @Test
  internal func exceptions() {
    let breakpoint = WindowsDebugControl.exception(STATUS_WX86_BREAKPOINT)
    let step = WindowsDebugControl.exception(STATUS_WX86_SINGLE_STEP)
    #expect(breakpoint == .breakpoint)
    #expect(step == .trace)
  }

  @Test
  internal func pseudoconsole() {
    var launch = Debuggee.Launch()
    #expect(WindowsPseudoConsole.enabled(launch) == false)
    launch.terminal = Debuggee.TerminalSize(columns: 80, rows: 24)
    #expect(WindowsPseudoConsole.enabled(launch))
    launch.output = "output.txt"
    #expect(WindowsPseudoConsole.enabled(launch) == false)
  }

  @Test
  internal func output() {
    let text = "debug output"
    var storage = Array(text.utf16) + [0]
    storage.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else {
        Issue.record("failed to allocate debug output")
        return
      }
      var information = OUTPUT_DEBUG_STRING_INFO()
      information.lpDebugStringData =
          UnsafeMutableRawPointer(base).assumingMemoryBound(to: CChar.self)
      information.fUnicode = 1
      information.nDebugStringLength = WORD(storage.count)
      var control = WindowsDebugControl()
      control.handle = GetCurrentProcess()
      control.output(information)
      guard let output = control.output else {
        Issue.record("failed to capture debug output")
        return
      }
      let expected = Array(text.utf8)
      #expect(output.count == expected.count)
      for index in 0 ..< min(output.count, expected.count) {
        #expect(output.bytes[index] == expected[index])
      }
      control.handle = nil
    }
  }

  @Test(arguments: 1019 ... 1025)
  internal func surrogate(_ count: Int) throws {
    let prefix = String(repeating: "a", count: count)
    let text = Array((prefix + "😀z\0").utf16)
    try text.withUnsafeBufferPointer { input in
      var info = OUTPUT_DEBUG_STRING_INFO()
      let address = UnsafeMutableRawPointer(mutating: input.baseAddress)
      info.lpDebugStringData = address?.assumingMemoryBound(to: CChar.self)
      info.nDebugStringLength = WORD(input.count)
      info.fUnicode = 1
      let output = try Debuggee.Output(info, handle: GetCurrentProcess())
      let bytes = (0 ..< output.count).map { output.bytes[$0] }
      let actual = String(decoding: bytes, as: UTF8.self)
      var expected = String(prefix.prefix(Configuration.OutputCapacity))
      if count + 4 <= Configuration.OutputCapacity {
        expected += "😀"
        if count + 5 <= Configuration.OutputCapacity {
          expected += "z"
        }
      }
      #expect(actual == expected)
      #expect(bytes == Array(expected.utf8))
    }
  }

  @Test(arguments: [1, 7, 8, 9, 10, 2054, 2055, 131072, 4194304])
  internal func notification(_ capacity: Int) throws {
    let process = ProcessIdentifier(rawValue: 7)
    var session = DebugSession()
    session.control.process = process
    var pending = Debuggee.Output()
    let count = min(Configuration.OutputCapacity, max(1, (capacity - 7) / 2))
    pending.count = count
    for index in 0 ..< count {
      pending.bytes[index] = 0xa5
    }
    session.control.output = pending
    var state = GDBRemoteSessionState(compatibility: .lldb, capacity: capacity)
    if capacity < 9 {
      #expect(throws: GDBHandlerError.capacity) {
        try session.record(process, state: &state)
      }
      #expect(session.control.output?.count == count)
      #expect(state.output.first == nil)
      return
    }
    try session.record(process, state: &state)
    let expected = Array(("O" + String(repeating: "a5", count: count)).utf8)
    #expect(state.output.first == expected)
    #expect(session.control.output == nil)
    #expect(state.stops.first == nil)
  }

  @Test
  internal func command() {
    let arguments = ["wait_for_attach"]
    let command = String(command: "a.exe", arguments: arguments.span)
    #expect(command == "a.exe wait_for_attach")
  }

  @Test(arguments: [("", "\"\""), ("plain", "plain"),
                    ("a b", "\"a b\""), ("a\"b", "\"a\\\"b\""),
                    ("a b\\", "\"a b\\\\\""), ("\\\"", "\"\\\\\\\"\""),
                    ("a\"\u{301}b", "\"a\\\"\u{301}b\""),
                    ("a \u{301}b", "\"a \u{301}b\""),
                    ("😀\"\u{301}", "\"😀\\\"\u{301}\"")])
  internal func quoting(_ pair: (String, String)) {
    #expect(String(quoting: pair.0) == pair.1)
  }

  @Test(arguments: [("echo DSX", "DSX\r\n"),
                    (#"echo "hello world""#, "\"hello world\"\r\n"),
                    (#"if "a b"=="a b" echo DSX"#, "DSX\r\n")])
  internal func capture(_ fixture: (String, String)) throws(Debuggee.Error) {
    var bytes = Array<UInt8>()
    var status: Debuggee.ProgramStatus?
    try bytes.append(addingCapacity: 64) { output throws(Debuggee.Error) in
      status =
          try Host.execute(fixture.0, directory: nil, timeout: 2, into: &output)
    }
    #expect(status == .completed(.exited(0)))
    #expect(bytes == Array(fixture.1.utf8))
  }

  @Test
  internal func drain() throws(Debuggee.Error) {
    var bytes = Array<UInt8>()
    let command = "for /L %i in (1,1,5000) do @echo DSX"
    try bytes.append(addingCapacity: 32768) { output throws(Debuggee.Error) in
      let status =
          try Host.execute(command, directory: nil, timeout: 5, into: &output)
      #expect(status == .completed(.exited(0)))
    }
    #expect(bytes == Array(String(repeating: "DSX\r\n", count: 5000).utf8))
  }

  @Test
  internal func redirect() throws {
    var buffer = Array<WCHAR>(repeating: 0, count: Int(MAX_PATH) + 1)
    let count = GetTempPathW(DWORD(buffer.count), &buffer)
    try #require(count > 0 && count < buffer.count)
    let temporary = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    let name = "DSX_REDIRECT_\(GetCurrentProcessId())"
    let directory = try WindowsPath.combine(temporary, name)
    try #require(withUTF16CString(directory) { CreateDirectoryW($0, nil) })
    defer {
      _ = withUTF16CString(directory) { RemoveDirectoryW($0) }
    }
    let path = try WindowsPath.combine(directory, "output.txt")
    defer {
      _ = withUTF16CString(path) { DeleteFileW($0) }
    }
    var config = Debuggee.Launch()
    config.output = "output.txt"
    let executable = try WindowsEnvironment["COMSPEC"]
    let command = "\(String(quoting: executable)) /d /c echo DSX"
    let child = try WindowsProcess(executable, command: command,
                                   directory: directory, errors: false,
                                   flags: CREATE_NO_WINDOW, config: config)
    #expect(try child.status(timeout: 5000) == .exited(0))
    let file = try NativeFileSystem.open(path, options: [.read], mode: 0)
    defer {
      try? NativeFileSystem.close(file)
    }
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: 32) { output throws(Debuggee.Error) in
      try NativeFileSystem.read(file, offset: 0, size: 32, into: &output)
    }
    #expect(bytes == Array("DSX\r\n".utf8))
  }

  @Test
  internal func server() throws {
    let path = CommandLine.arguments[0]
    guard let directory = try WindowsPath.parent(path) else {
      Issue.record("failed to resolve the DSX product directory")
      return
    }
    let executable = try WindowsPath.combine(directory, "dsx.exe")
    var session = PlatformSession(executable: executable)
    let child = try session.launch()
    #expect(child.port > 0)
    try session.remove(child.process)
    try session.close()
  }

  @Test
  internal func termination() throws {
    var buffer = Array<WCHAR>(repeating: 0, count: Int(MAX_PATH))
    let count = buffer.withUnsafeMutableBufferPointer { buffer in
      GetSystemDirectoryW(buffer.baseAddress, UINT(buffer.count))
    }
    guard count > 0, Int(count) < buffer.count else {
      Issue.record("failed to resolve the Windows system directory")
      return
    }
    let system = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    let executable = try WindowsPath.combine(system, "cmd.exe")
    let arguments = ["/d", "/c", "exit", "7"]
    let command = String(command: executable, arguments: arguments.span)
    let child = try WindowsProcess(executable, command: command, directory: nil,
                                   errors: false, flags: CREATE_NO_WINDOW)
    #expect(throws: Debuggee.Error.exited(7)) {
      try child.notification()
    }
  }
}
#endif
