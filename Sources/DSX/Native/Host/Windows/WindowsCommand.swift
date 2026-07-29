// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsCommand {
  private typealias Failure = Debuggee.Error

  private let application: Array<WCHAR>
  private var command: Array<WCHAR>
  private let environment: Array<WCHAR>
  private let directory: Array<WCHAR>

  internal init(_ executable: String, arguments: borrowing Span<String>,
                directory: String?,
                environment: borrowing Span<Debuggee.Environment>)
      throws(Debuggee.Error) {
    let command = String(command: executable, arguments: arguments)
    try self.init(executable, command: command, directory: directory,
                  environment: environment)
  }

  internal init(_ executable: String, command: String, directory: String?,
                environment: borrowing Span<Debuggee.Environment>)
      throws(Debuggee.Error) {
    let application = Array(executable.utf16) + [0]
    let command = Array(command.utf16) + [0]
    let working = directory.map { Array($0.utf16) + [0] } ?? []
    guard application.span.terminated, command.span.terminated,
        working.isEmpty || working.span.terminated else {
      throw .process
    }
    let environment: Array<WCHAR> = if environment.isEmpty {
      [0]
    } else {
      try Array(environment, inheriting: WindowsEnvironment.read())
    }
    self.application = application
    self.command = command
    self.directory = working
    self.environment = environment
  }

  internal mutating func create(_ startup: inout STARTUPINFOW,
                                console: HANDLE? = nil, flags: DWORD)
      throws(Debuggee.Error) -> PROCESS_INFORMATION {
    var handles: InlineArray<3, HANDLE?> =
        [startup.hStdInput, startup.hStdOutput, startup.hStdError]
    var count = 0
    for index in 0 ..< handles.count {
      guard let handle = handles[index] else {
        continue
      }
      if index > 0 && handle == startup.hStdInput ||
          index > 1 && handle == startup.hStdOutput {
        continue
      }
      handles[count] = handle
      count += 1
    }
    guard console != nil || count > 0 else {
      return try start(&startup, inherit: false, flags: flags)
    }
    let key = if console == nil {
      PROC_THREAD_ATTRIBUTE_HANDLE_LIST
    } else {
      PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
    }
    let size = SIZE_T((console == nil ? count : 1) * MemoryLayout<HANDLE>.size)
    var capacity: SIZE_T = 0
    _ = InitializeProcThreadAttributeList(nil, 1, 0, &capacity)
    guard capacity > 0 else {
      throw Debuggee.Error(process: GetLastError())
    }
    let alignment = MemoryLayout<UInt>.alignment
    return try withUnsafeTemporaryAllocation(byteCount: Int(capacity),
                                             alignment: alignment,
                                             { storage throws(Failure) in
      let list = OpaquePointer(storage.baseAddress!)
      guard InitializeProcThreadAttributeList(list, 1, 0, &capacity) else {
        throw Debuggee.Error(process: GetLastError())
      }
      return try withUnsafeMutableBytes(of: &handles) { bytes throws(Failure) in
        defer {
          DeleteProcThreadAttributeList(list)
        }
        let value = console ?? bytes.baseAddress!
        guard UpdateProcThreadAttribute(list, 0, key, value, size, nil,
                                        nil) else {
          throw Debuggee.Error(process: GetLastError())
        }
        var extended = STARTUPINFOEXW()
        extended.StartupInfo = startup
        extended.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        extended.lpAttributeList = list
        // Keep the complete structure, not an inout copy of its prefix.
        return try withUnsafeMutablePointer(to: &extended,
                                            { pointer throws(Failure) in
          try pointer.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1,
                                        { startup throws(Failure) in
            try start(startup, inherit: console == nil,
                      flags: flags | EXTENDED_STARTUPINFO_PRESENT)
          })
        })
      }
    })
  }

  private mutating func start(_ startup: UnsafeMutablePointer<STARTUPINFOW>,
                              inherit: Bool, flags: DWORD)
      throws(Debuggee.Error) -> PROCESS_INFORMATION {
    var information = PROCESS_INFORMATION()
    let created = application.withUnsafeBufferPointer { application in
      command.withUnsafeMutableBufferPointer { command in
        environment.withUnsafeBufferPointer { environment in
          let variables: UnsafeMutablePointer<WCHAR>? =
              environment.count > 1
                  ? UnsafeMutablePointer(mutating: environment.baseAddress) : nil
          return directory.withUnsafeBufferPointer { working in
            let directory = working.isEmpty ? nil : working.baseAddress
            return CreateProcessW(application.baseAddress, command.baseAddress,
                                  nil, nil, inherit, flags, variables,
                                  directory, startup, &information)
          }
        }
      }
    }
    guard created else {
      throw .launch(CInt(bitPattern: GetLastError()))
    }
    return information
  }
}

extension Span where Element == WCHAR {
  fileprivate var terminated: Bool {
    guard count > 0, self[count - 1] == 0 else {
      return false
    }
    for index in 0 ..< count - 1 where self[index] == 0 {
      return false
    }
    return true
  }
}
#endif
