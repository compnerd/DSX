// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import DSXShims
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsFileSystemTests {
  @Test
  internal func collision() throws {
    let name = "dsx-collision-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, working: temporary())
    let handle =
        try NativeFileSystem.open(path, options: [.create, .exclusive], mode: 0)
    try NativeFileSystem.close(handle)
    defer {
      try? NativeFileSystem.remove(path)
    }
    #expect(throws: Debuggee.Error.self) {
      try NativeFileSystem.create(path, mode: 0o700)
    }
    #expect(throws: Debuggee.Error.self) {
      _ = try NativeFileSystem.destination(path)
    }
  }

  @Test(.enabled(if: symlinks(), "Requires Windows symbolic-link privilege"))
  internal func symbolic() throws {
    let name = "dsx-symbolic-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, working: temporary())
    let target = "missing-relative-target"
    try NativeFileSystem.link(target, at: path)
    defer {
      try? NativeFileSystem.remove(path)
    }
    #expect(try NativeFileSystem.destination(path) == target)
    let metadata = try NativeFileSystem.status(path, link: true)
    #expect(metadata.mode & 0o170000 == 0o120000)
    #expect(throws: Debuggee.Error.self) {
      _ = try NativeFileSystem.status(path, link: false)
    }
  }

  @Test
  internal func junction() throws {
    let name = "dsx-junction-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, working: temporary())
    let target =
        try NativeFileSystem.resolve(name + "-missing", working: temporary())
    try NativeFileSystem.create(path, mode: 0o700)
    defer {
      remove(path)
    }
    let raw = path.withCString(encodedAs: UTF16.self) { path in
      let sharing: DWORD =
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
      let flags: DWORD =
          FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS
      return CreateFileW(path, GENERIC_WRITE, sharing, nil, OPEN_EXISTING,
                         flags, nil)
    }
    let handle = try #require(raw)
    try #require(UInt(bitPattern: handle) != UInt.max)
    defer {
      _ = CloseHandle(handle)
    }
    let text = Array((#"\??\"# + target).utf16)
    var header = dsx_reparse_names()
    header.ReparseTag = DSX::IO_REPARSE_TAG_MOUNT_POINT
    header.ReparseDataLength = USHORT(8 + (text.count + 2) * 2)
    header.SubstituteNameLength = USHORT(text.count * 2)
    header.PrintNameOffset = USHORT((text.count + 1) * 2)
    var bytes = withUnsafeBytes(of: header) { Array($0) }
    text.withUnsafeBytes { bytes.append(contentsOf: $0) }
    bytes.append(contentsOf: [0, 0, 0, 0])
    var count: DWORD = 0
    let status = bytes.withUnsafeMutableBytes { bytes in
      DeviceIoControl(handle, DSX::FSCTL_SET_REPARSE_POINT, bytes.baseAddress,
                      DWORD(bytes.count), nil, 0, &count, nil)
    }
    try #require(status, "FSCTL_SET_REPARSE_POINT: \(GetLastError())")
    #expect(try NativeFileSystem.destination(path) == target)
    let metadata = try NativeFileSystem.status(path, link: true)
    #expect(metadata.mode & 0o170000 == 0o120000)
    #expect(throws: Debuggee.Error.self) {
      try NativeFileSystem.create(path, mode: 0o700)
    }
  }

  @Test
  internal func empty() throws {
    let name = "dsx-empty-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, working: temporary())
    let options: FileOptions = [.create, .exclusive, .write]
    let handle = try NativeFileSystem.open(path, options: options, mode: 0)
    defer {
      try? NativeFileSystem.remove(path)
    }
    try NativeFileSystem.close(handle)
    #expect(throws: Debuggee.Error.process) {
      _ = try WindowsMappedFile(path)
    }
  }

  @Test
  internal func resolve() throws(Debuggee.Error) {
    let relative =
        try NativeFileSystem.resolve("nested/../target",
                                     working: #"C:/root/work"#)
    #expect(relative == #"C:\root\work\target"#)
    let absolute =
        try NativeFileSystem.resolve(#"D:/tmp/../target"#,
                                     working: #"C:\root\work"#)
    #expect(absolute == #"D:\target"#)
  }

  @Test
  internal func directory() throws(Debuggee.Error) {
    let root =
        try NativeFileSystem.resolve("dsx-path-\(GetCurrentProcessId())",
                                     working: temporary())
    let first = try NativeFileSystem.resolve("first", working: root)
    let child =
        try NativeFileSystem.resolve("first/../first/second", working: root)
    defer {
      remove(child)
      remove(first)
      remove(root)
    }
    try NativeFileSystem.create(child, mode: 0o700)
    try NativeFileSystem.create(child, mode: 0o700)
    let status = try NativeFileSystem.status(child, link: false)
    #expect(status.mode & 0o170000 == 0o040000)
  }
}

private func temporary() throws(Debuggee.Error) -> String {
  var path = Array<WCHAR>(repeating: 0, count: 261)
  let count = path.withUnsafeMutableBufferPointer { path in
    GetTempPathW(DWORD(path.count), path.baseAddress)
  }
  guard count > 0, Int(count) < path.count else {
    throw .system(CInt(bitPattern: GetLastError()))
  }
  return String(decoding: path[0 ..< Int(count)], as: UTF16.self)
}

private func symlinks() -> Bool {
  guard let directory = try? temporary() else {
    return true
  }
  let path = directory + "dsx-link-capability-\(GetCurrentProcessId())"
  do {
    try NativeFileSystem.link("missing", at: path)
    try NativeFileSystem.remove(path)
    return true
  } catch Debuggee.Error.system(CInt(WinSDK.ERROR_PRIVILEGE_NOT_HELD)) {
    return false
  } catch {
    return true
  }
}

private func remove(_ path: String) {
  _ = path.withCString(encodedAs: UTF16.self) { path in
    RemoveDirectoryW(path)
  }
}
#endif
