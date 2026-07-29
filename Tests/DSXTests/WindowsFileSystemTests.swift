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
  internal func matching() {
    let path = Array("C:\\tmp\\\u{00e9}.dll".utf8)
    let ordinal = WindowsFileSystem.matches(path.span, "c:/TMP/\u{00c9}.DLL",
                                            component: false)
    #expect(ordinal)
    let component = WindowsFileSystem.matches(path.span, "\u{00c9}.DLL",
                                              component: true)
    #expect(component)
    let composed =
        WindowsFileSystem.matches(path.span, "C:\\tmp\\e\u{0301}.dll",
                                  component: false)
    #expect(composed == false)
    let decomposed = WindowsFileSystem.matches(path.span, "e\u{0301}.dll",
                                               component: true)
    #expect(decomposed == false)
    let embedded = Array("\u{00e9}\0a".utf8)
    let nul = WindowsFileSystem.matches(embedded.span, "\u{00e9}\0b",
                                        component: false)
    #expect(nul == false)
    let prefix = String(repeating: "a", count: 300)
    let long = Array((prefix + "\\\u{00e9}.dll").utf8)
    let heap = WindowsFileSystem.matches(long.span, prefix + "/\u{00c9}.DLL",
                                         component: false)
    #expect(heap)
  }

  @Test
  internal func completion() throws {
    let name = "dsx-completion-\(GetCurrentProcessId())"
    let root = try NativeFileSystem.resolve(name, directory: temporary())
    let directory = try NativeFileSystem.resolve("directory", directory: root)
    let file = try NativeFileSystem.resolve("file", directory: root)
    try NativeFileSystem.create(directory, mode: 0o700)
    defer {
      try? NativeFileSystem.remove(file)
      remove(directory)
      remove(root)
    }
    let options: FileOptions = [.create, .exclusive, .write]
    let handle = try NativeFileSystem.open(file, options: options, mode: 0o600)
    try NativeFileSystem.close(handle)
    let prefix = root + "\\"
    let entries = try NativeFileSystem.complete(prefix, directories: false)
    #expect(entries == [directory + "\\", file])
    let folders = try NativeFileSystem.complete(prefix, directories: true)
    #expect(folders == [directory + "\\"])
  }

  @Test
  internal func current() throws {
    // A relative fixture avoids changing the process-wide working directory.
    let name = "dsx-current-\(GetCurrentProcessId())"
    try NativeFileSystem.create(name, mode: 0o700)
    defer {
      remove(name)
    }
    for directories in [false, true] {
      let entries = try NativeFileSystem.complete("", directories: directories)
      #expect(entries.contains(name + "\\"))
    }
  }

  @Test
  internal func append() async throws {
    let name = "dsx-append-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
    let options: FileOptions = [.create, .exclusive, .read, .write, .append]
    let first = try NativeFileSystem.open(path, options: options, mode: 0o600)
    defer {
      try? NativeFileSystem.close(first)
      try? NativeFileSystem.remove(path)
    }
    let second =
        try NativeFileSystem.open(path, options: [.write, .append], mode: 0)
    defer {
      try? NativeFileSystem.close(second)
    }
    let repetitions = 2000
    let width = 16
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (index, handle) in [first, second].enumerated() {
        group.addTask {
          let bytes = Array(repeating: UInt8(index), count: width)
          for _ in 0 ..< repetitions {
            let count =
                try NativeFileSystem.write(handle, offset: UInt64.max,
                                           bytes: bytes.span)
            #expect(count == width)
          }
        }
      }
      try await group.waitForAll()
    }
    let count = repetitions * width * 2
    #expect(try NativeFileSystem.size(first) == UInt64(count))
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: count) { output throws(Debuggee.Error) in
      try NativeFileSystem.read(first, offset: 0, size: count, into: &output)
    }
    #expect(bytes.count == count)
    #expect(bytes.filter { $0 == 0 }.count == repetitions * width)
    #expect(bytes.filter { $0 == 1 }.count == repetitions * width)
    var tail = Array<UInt8>()
    try tail.append(addingCapacity: width) { output throws(Debuggee.Error) in
      try NativeFileSystem.read(first, offset: UInt64(count), size: width,
                                into: &output)
    }
    #expect(tail.isEmpty)
  }

  @Test
  internal func offsets() throws {
    let name = "dsx-offsets-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
    let options: FileOptions = [.create, .exclusive, .write]
    let handle = try NativeFileSystem.open(path, options: options, mode: 0o600)
    defer {
      try? NativeFileSystem.close(handle)
      try? NativeFileSystem.remove(path)
    }
    let bytes: Array<UInt8> = [1, 2, 3]
    let written =
        try NativeFileSystem.write(handle, offset: 4, bytes: bytes.span)
    #expect(written == 3)
    #expect(try NativeFileSystem.size(handle) == 7)
    #expect(throws: Debuggee.Error.self) {
      _ = try NativeFileSystem.write(handle, offset: UInt64.max,
                                     bytes: bytes.span)
    }
    let truncation: FileOptions = [.write, .truncate, .append]
    let append = try NativeFileSystem.open(path, options: truncation, mode: 0)
    defer {
      try? NativeFileSystem.close(append)
    }
    #expect(try NativeFileSystem.size(append) == 0)
    let appended =
        try NativeFileSystem.write(append, offset: 4, bytes: bytes.span)
    #expect(appended == 3)
    #expect(try NativeFileSystem.size(append) == 3)
  }

  @Test(.enabled(if: symlinks(), "Requires Windows symbolic-link privilege"))
  internal func relative() throws {
    let name = "dsx-directory-link-\(GetCurrentProcessId())"
    let root = try NativeFileSystem.resolve(name, directory: temporary())
    let target = try NativeFileSystem.resolve("target", directory: root)
    let path = try NativeFileSystem.resolve("link", directory: root)
    try NativeFileSystem.create(target, mode: 0o700)
    defer {
      try? NativeFileSystem.remove(path)
      remove(target)
      remove(root)
    }
    try NativeFileSystem.link("target", at: path)
    #expect(try NativeFileSystem.destination(path) == "target")
    let status = try NativeFileSystem.status(path, link: false)
    #expect(status.mode & 0o170000 == 0o040000)
    remove(target)
    try NativeFileSystem.remove(path)
    #expect(throws: Debuggee.Error.self) {
      _ = try NativeFileSystem.status(path, link: true)
    }
    #expect(throws: Debuggee.Error.self) {
      try NativeFileSystem.remove(root)
    }
  }

  @Test
  internal func permissions() throws {
    let name = "dsx-permissions-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
    let options: FileOptions = [.create, .exclusive, .write]
    let handle = try NativeFileSystem.open(path, options: options, mode: 0)
    try NativeFileSystem.close(handle)
    defer {
      try? NativeFileSystem.permissions(path, mode: 0o700)
      try? NativeFileSystem.remove(path)
    }
    let original = path.withCString(encodedAs: UTF16.self) { path in
      GetFileAttributesW(path)
    }
    for mode: UInt32 in [0o500, 0o700] {
      try NativeFileSystem.permissions(path, mode: mode)
      let status = try NativeFileSystem.status(path, link: false)
      #expect(status.mode & 0o700 == UInt64(mode))
      let attributes = path.withCString(encodedAs: UTF16.self) { path in
        GetFileAttributesW(path)
      }
      #expect(attributes & ~DSX::FILE_ATTRIBUTE_READONLY == original)
    }
  }

  @Test(.enabled(if: symlinks(), "Requires Windows symbolic-link privilege"))
  internal func size() throws {
    let name = "dsx-size-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
    try NativeFileSystem.link(#filePath, at: path)
    defer {
      try? NativeFileSystem.remove(path)
    }
    let handle = try NativeFileSystem.open(path, options: [.read], mode: 0)
    defer {
      try? NativeFileSystem.close(handle)
    }
    #expect(try NativeFileSystem.size(path) == NativeFileSystem.size(handle))
  }

  @Test
  internal func collision() throws {
    let name = "dsx-collision-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
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
    let path = try NativeFileSystem.resolve(name, directory: temporary())
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
    #expect(throws: Debuggee.Error.self) {
      _ = try NativeFileSystem.size(path)
    }
  }

  @Test
  internal func junction() throws {
    let name = "dsx-junction-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
    let target =
        try NativeFileSystem.resolve(name + "-missing", directory: temporary())
    try NativeFileSystem.create(path, mode: 0o700)
    defer {
      remove(path)
    }
    let raw = path.withCString(encodedAs: UTF16.self) { path in
      let sharing: DWORD =
          DSX::FILE_SHARE_READ | DSX::FILE_SHARE_WRITE | DSX::FILE_SHARE_DELETE
      let flags: DWORD =
          DSX::FILE_FLAG_OPEN_REPARSE_POINT | DSX::FILE_FLAG_BACKUP_SEMANTICS
      return CreateFileW(path, DSX::GENERIC_WRITE, sharing, nil,
                         DSX::OPEN_EXISTING, flags, nil)
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
    try NativeFileSystem.remove(path)
  }

  @Test
  internal func empty() throws {
    let name = "dsx-empty-\(GetCurrentProcessId())"
    let path = try NativeFileSystem.resolve(name, directory: temporary())
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
                                     directory: #"C:/root/work"#)
    #expect(relative == #"C:\root\work\target"#)
    let absolute =
        try NativeFileSystem.resolve(#"D:/tmp/../target"#,
                                     directory: #"C:\root\work"#)
    #expect(absolute == #"D:\target"#)
  }

  @Test
  internal func directory() throws(Debuggee.Error) {
    let root =
        try NativeFileSystem.resolve("dsx-path-\(GetCurrentProcessId())",
                                     directory: temporary())
    let first = try NativeFileSystem.resolve("first", directory: root)
    let child =
        try NativeFileSystem.resolve("first/../first/second", directory: root)
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
