// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsProcess {
  private typealias Failure = Debuggee.Error

  @inline(never)
  internal static func create(_ application: inout Array<WCHAR>,
                              command: inout Array<WCHAR>,
                              environment: inout Array<WCHAR>,
                              directory working: inout Array<WCHAR>,
                              startup: inout STARTUPINFOW,
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
      return try start(&application, command: &command,
                       environment: &environment, directory: &working,
                       startup: &startup, inherit: false, flags: flags)
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
      throw failure(GetLastError())
    }
    let alignment = MemoryLayout<UInt>.alignment
    return try withUnsafeTemporaryAllocation(byteCount: Int(capacity),
                                             alignment: alignment,
                                             { storage throws(Failure) in
      let list = OpaquePointer(storage.baseAddress!)
      guard InitializeProcThreadAttributeList(list, 1, 0, &capacity) else {
        throw failure(GetLastError())
      }
      return try withUnsafeMutableBytes(of: &handles) { bytes throws(Failure) in
        defer {
          DeleteProcThreadAttributeList(list)
        }
        let value = console ?? bytes.baseAddress!
        guard UpdateProcThreadAttribute(list, 0, key, value, size, nil,
                                        nil) else {
          throw failure(GetLastError())
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
            try start(&application, command: &command,
                      environment: &environment, directory: &working,
                      startup: startup, inherit: console == nil,
                      flags: flags | EXTENDED_STARTUPINFO_PRESENT)
          })
        })
      }
    })
  }

  @inline(never)
  private static func start(_ application: inout Array<WCHAR>,
                            command: inout Array<WCHAR>,
                            environment: inout Array<WCHAR>,
                            directory working: inout Array<WCHAR>,
                            startup: UnsafeMutablePointer<STARTUPINFOW>,
                            inherit: Bool, flags: DWORD) throws(Debuggee.Error)
      -> PROCESS_INFORMATION {
    var information = PROCESS_INFORMATION()
    let created = application.withUnsafeMutableBufferPointer { application in
      command.withUnsafeMutableBufferPointer { command in
        environment.withUnsafeMutableBufferPointer { environment in
          let variables: UnsafeMutablePointer<WCHAR>? =
              environment.count > 1 ? environment.baseAddress : nil
          return working.withUnsafeMutableBufferPointer { working in
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

  @inline(never)
  internal static func redirect(_ path: String?, standard: DWORD, access: DWORD,
                                creation: DWORD,
                                directory working: String? = nil,
                                security: inout SECURITY_ATTRIBUTES)
      throws(Debuggee.Error) -> WindowsRedirection {
    guard let path else {
      let handle = GetStdHandle(standard)
      if handle == INVALID_HANDLE_VALUE {
        throw failure(GetLastError())
      }
      guard let handle else {
        return .borrowed(nil)
      }
      var duplicate: HANDLE?
      let process = GetCurrentProcess()
      guard DuplicateHandle(process, handle, process, &duplicate, 0, true,
                            DWORD(DUPLICATE_SAME_ACCESS)),
          let owned = WindowsHandle(duplicate) else {
        throw failure(GetLastError())
      }
      return .owned(owned)
    }
    let resolved = try WindowsFileSystem.resolve(path, working: working)
    let handle = withUTF16CString(resolved) { path in
      CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, &security,
                  creation, FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let handle = WindowsHandle(handle) else {
      throw failure(GetLastError())
    }
    return .owned(handle)
  }

  @inline(never)
  internal static func environment(_ env: borrowing Span<Debuggee.Environment>)
      throws(Debuggee.Error) -> Array<WCHAR> {
    guard !env.isEmpty else {
      return [0]
    }
    return try ProcessEnvironment.resolve(env,
                                          inheriting: WindowsEnvironment.read())
  }
}
#endif
