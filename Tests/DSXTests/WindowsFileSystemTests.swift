// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsFileSystemTests {
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

private func remove(_ path: String) {
  _ = path.withCString(encodedAs: UTF16.self) { path in
    RemoveDirectoryW(path)
  }
}
#endif
