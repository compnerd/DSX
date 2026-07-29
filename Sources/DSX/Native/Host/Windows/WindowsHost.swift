// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension Host {
  internal static var working: String? {
    let capacity = GetCurrentDirectoryW(0, nil)
    guard capacity > 0 else {
      return nil
    }
    var buffer = Array<WCHAR>(repeating: 0, count: Int(capacity))
    let count = buffer.withUnsafeMutableBufferPointer { buffer in
      GetCurrentDirectoryW(DWORD(buffer.count), buffer.baseAddress)
    }
    guard count > 0, count < capacity else {
      return nil
    }
    return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
  }

  internal static func launch(_ executable: String,
                              arguments: borrowing Span<String>)
      throws(Debuggee.Error) -> HostProcess {
    var config = Debuggee.Launch()
    if let runtime = try SwiftRuntime.locate() {
      let path = (try? WindowsEnvironment["PATH"]) ?? ""
      let value = runtime + ";" + path
      let entry = Debuggee.Environment(name: "PATH", value: value)
      config.environment.append(entry)
    }
    let command = WindowsProcess.command(executable, arguments: arguments)
    let child = try WindowsProcess(executable, command: command, directory: nil,
                                   errors: false,
                                   flags: CREATE_NEW_PROCESS_GROUP,
                                   config: config)
    let port: UInt16
    do {
      port = try child.notification()
    } catch {
      try? child.terminate()
      throw error
    }
    let process = child.process
    return HostProcess(process: process, port: port, monitor: child.monitor())
  }

  internal static func spawn(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> HostProcess {
    guard let executable = config.executable else {
      throw .process
    }
    let command =
        WindowsProcess.command(executable, arguments: config.arguments.span)
    let child = try WindowsProcess(executable, command: command,
                                   directory: config.working, errors: false,
                                   flags: CREATE_NEW_PROCESS_GROUP,
                                   config: config, capture: false)
    let process = child.process
    return HostProcess(process: process, port: 0, monitor: child.monitor())
  }

  internal static func execute(_ command: String, directory working: String?,
                               timeout: UInt64,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let shell = try WindowsEnvironment["COMSPEC"]
    let executable = WindowsProcess.quote(shell)
    let invocation = "\(executable) /d /s /c \"\(command)\""
    let child = try WindowsProcess(shell, command: invocation,
                                   directory: working, errors: true,
                                   flags: CREATE_NO_WINDOW)
    return try child.wait(timeout, into: &output)
  }

  internal static func user(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    try WindowsEnvironment["USERNAME"]
  }

  internal static func group(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    try WindowsEnvironment["USERNAME"]
  }
}

private enum SwiftRuntime {
  internal static func locate() throws(Debuggee.Error) -> String? {
    let name: StaticString = "swiftCore.dll"
    let value = InlineArray<14, WCHAR> { index in
      index < name.utf8CodeUnitCount ? WCHAR(name.utf8Start[index]) : 0
    }
    let module = value.span.withUnsafeBufferPointer { value in
      GetModuleHandleW(value.baseAddress)
    }
    guard let module else {
      return nil
    }
    var capacity = Int(MAX_PATH)
    while true {
      var buffer = Array<WCHAR>(repeating: 0, count: capacity)
      let count = buffer.withUnsafeMutableBufferPointer { buffer in
        GetModuleFileNameW(module, buffer.baseAddress, DWORD(buffer.count))
      }
      guard count > 0 else {
        throw WindowsProcess.failure(GetLastError())
      }
      if Int(count) < buffer.count {
        guard try WindowsPath.parent(&buffer) else {
          throw .state
        }
        return String(decodingCString: buffer, as: UTF16.self)
      }
      capacity *= 2
    }
  }
}

#endif
