// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import DSXShims
internal import WinSDK

internal struct WindowsFileHandle: Sendable {
  fileprivate let raw: UInt
  fileprivate let append: Bool

  fileprivate var handle: HANDLE {
    HANDLE(bitPattern: raw)!
  }
}

internal enum WindowsFileSystem {
  internal static let separator = UInt8(ascii: "\\")

  internal typealias Handle = WindowsFileHandle
  internal typealias Root = Never
  private typealias Failure = Debuggee.Error

  internal static func canonical(_ path: String) throws(Debuggee.Error)
      -> String {
    try WindowsPath.canonical(path)
  }

  internal static func create(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    try folder(WindowsPath.canonical(path))
  }

  internal static func complete(_ path: String, directories: Bool)
      throws(Debuggee.Error) -> Array<String> {
    let path = try path.isEmpty ? "" : WindowsPath.canonical(path)
    let parent = try WindowsPath.parent(path)
    let base = parent ?? (WindowsPath.root(path) ? path : "")
    var data = WIN32_FIND_DATAW()
    let handle = withUTF16CString(path + "*") { path in
      FindFirstFileW(path, &data)
    }
    guard let handle else {
      let code = GetLastError()
      if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND {
        return []
      }
      throw Debuggee.Error(windows: code)
    }
    if handle == INVALID_HANDLE_VALUE {
      let code = GetLastError()
      if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND {
        return []
      }
      throw Debuggee.Error(windows: code)
    }
    defer {
      _ = FindClose(handle)
    }
    var completions = Array<String>()
    repeat {
      let name = decode(&data.cFileName)
      if name == "." || name == ".." {
        continue
      }
      let directory = data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
      if directories {
        guard directory else {
          continue
        }
      }
      try completions.append(WindowsPath.combine(base, name,
                                                 trailing: directory))
    } while FindNextFileW(handle, &data)
    let code = GetLastError()
    guard code == ERROR_NO_MORE_FILES else {
      throw Debuggee.Error(windows: code)
    }
    completions.order(by: <)
    return completions
  }

  @inline(never)
  internal static func resolve(_ path: String, directory: String?)
      throws(Debuggee.Error) -> String {
    if let directory {
      try WindowsPath.combine(directory, path)
    } else {
      try WindowsPath.canonical(path)
    }
  }

  internal static func root(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Root? {
    _ = process
    return nil
  }

  internal static func open(_ path: String, options: FileOptions, mode: UInt32,
                            root _: borrowing Root? = nil)
      throws(Debuggee.Error) -> WindowsFileHandle {
    let access = (options.contains(.read) ? GENERIC_READ : 0)
               | (options.contains(.write) ? GENERIC_WRITE : 0)
    let create = options.contains(.create)
    let truncate = options.contains(.truncate)
    let exclusive = options.contains(.exclusive)
    let creation: DWORD = switch (create, truncate, exclusive) {
    case (true, _, true): CREATE_NEW
    case (true, true, false): CREATE_ALWAYS
    case (true, false, false): OPEN_ALWAYS
    case (false, true, _): TRUNCATE_EXISTING
    case (false, false, _): OPEN_EXISTING
    }
    let handle = withUTF16CString(path) { path in
      CreateFileW(path, access,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nil,
                  creation, FILE_ATTRIBUTE_NORMAL, nil)
    }
    if handle == INVALID_HANDLE_VALUE {
      throw Debuggee.Error(windows: GetLastError())
    }
    return WindowsFileHandle(raw: UInt(bitPattern: handle),
                             append: options.contains(.append))
  }

  @inline(never)
  internal static func close(_ handle: WindowsFileHandle)
      throws(Debuggee.Error) {
    guard CloseHandle(handle.handle) else {
      throw Debuggee.Error(windows: GetLastError())
    }
  }

  internal static func read(_ handle: WindowsFileHandle, offset: UInt64,
                            size: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    var position = try OVERLAPPED(offset: offset)
    try output.withUnsafeMutableBufferPointer { data, offset throws(Failure) in
      guard let base = data.baseAddress else {
        return
      }
      let available = min(size, data.count - offset)
      let requested = DWORD(clamping: available)
      var count: DWORD = 0
      let status =
          ReadFile(handle.handle, base.advanced(by: offset), requested, &count,
                   &position)
      if status == false {
        let code = GetLastError()
        guard code == ERROR_HANDLE_EOF else {
          throw Debuggee.Error(windows: code)
        }
      }
      offset += Int(count)
    }
  }

  internal static func write(_ handle: WindowsFileHandle, offset: UInt64,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    // The kernel selects EOF as part of the write, without a separate seek.
    var position = try OVERLAPPED(offset: offset, append: handle.append)
    return try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      var count: DWORD = 0
      let requested = DWORD(clamping: bytes.count)
      let status =
          WriteFile(handle.handle, bytes.baseAddress, requested, &count,
                    &position)
      guard status else {
        throw Debuggee.Error(windows: GetLastError())
      }
      return Int(count)
    }
  }

  internal static func remove(_ path: String, root _: borrowing Root? = nil)
      throws(Debuggee.Error) {
    let status = withUTF16CString(path) { path in
      let attributes = GetFileAttributesW(path)
      let directory = FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT
      if attributes != INVALID_FILE_ATTRIBUTES,
          attributes & directory == directory {
        return RemoveDirectoryW(path)
      }
      return DeleteFileW(path)
    }
    guard status else {
      throw Debuggee.Error(windows: GetLastError())
    }
  }

  internal static func link(_ target: String, at path: String,
                            root _: borrowing Root? = nil)
      throws(Debuggee.Error) {
    let resolved = try resolve(target, directory: WindowsPath.parent(path))
    let attributes = withUTF16CString(resolved) { path in
      GetFileAttributesW(path)
    }
    let code = withUTF16CString(target) { target in
      withUTF16CString(path) { path in
        var flags = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
        if attributes != INVALID_FILE_ATTRIBUTES,
            attributes & FILE_ATTRIBUTE_DIRECTORY > 0 {
          flags |= SYMBOLIC_LINK_FLAG_DIRECTORY
        }
        while CreateSymbolicLinkW(path, target, flags) == 0 {
          let code = GetLastError()
          guard code == ERROR_INVALID_PARAMETER,
              flags & SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE > 0 else {
            return code
          }
          flags &= ~SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
        }
        return ERROR_SUCCESS
      }
    }
    guard code == ERROR_SUCCESS else {
      throw Debuggee.Error(windows: code)
    }
  }

  internal static func permissions(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    let code = withUTF16CString(path) { path in
      var attributes = GetFileAttributesW(path)
      if attributes == INVALID_FILE_ATTRIBUTES {
        return GetLastError()
      }
      if mode & 0o222 > 0 {
        attributes &= ~FILE_ATTRIBUTE_READONLY
        if attributes == 0 {
          attributes = FILE_ATTRIBUTE_NORMAL
        }
      } else {
        attributes |= FILE_ATTRIBUTE_READONLY
        attributes &= ~FILE_ATTRIBUTE_NORMAL
      }
      guard SetFileAttributesW(path, attributes) else {
        return GetLastError()
      }
      return ERROR_SUCCESS
    }
    guard code == ERROR_SUCCESS else {
      throw Debuggee.Error(windows: code)
    }
  }

  internal static func size(_ path: String, root _: borrowing Root? = nil)
      throws(Debuggee.Error) -> UInt64 {
    try status(path, link: false).size
  }

  internal static func size(_ handle: WindowsFileHandle) throws(Debuggee.Error)
      -> UInt64 {
    var value = LARGE_INTEGER()
    guard GetFileSizeEx(handle.handle, &value), value.QuadPart >= 0 else {
      throw Debuggee.Error(windows: GetLastError())
    }
    return UInt64(value.QuadPart)
  }

  @inline(never)
  internal static func status(_ path: String, link: Bool,
                              root _: borrowing Root? = nil)
      throws(Debuggee.Error) -> FileStatus {
    let handle = try inspect(path, reparse: link)
    let file =
        WindowsFileHandle(raw: UInt(bitPattern: handle.value), append: false)
    return try status(file)
  }

  internal static func destination(_ path: String,
                                   root _: borrowing Root? = nil)
      throws(Debuggee.Error) -> String {
    let handle = try inspect(path, reparse: true)
    let capacity = Int(MAXIMUM_REPARSE_DATA_BUFFER_SIZE)
    return try withUnsafeTemporaryAllocation(byteCount: capacity, alignment: 4,
                                             { bytes throws(Failure) in
      var count: DWORD = 0
      let status = DeviceIoControl(handle.value, FSCTL_GET_REPARSE_POINT, nil,
                                   0, bytes.baseAddress, DWORD(capacity),
                                   &count, nil)
      guard status else {
        throw Debuggee.Error(windows: GetLastError())
      }
      let buffer = UnsafeRawBufferPointer(rebasing: bytes[..<Int(count)])
      return try String(reparse: buffer)
    })
  }

  internal static func status(_ handle: WindowsFileHandle)
      throws(Debuggee.Error) -> FileStatus {
    var info = BY_HANDLE_FILE_INFORMATION()
    guard GetFileInformationByHandle(handle.handle, &info) else {
      throw Debuggee.Error(windows: GetLastError())
    }
    let directory = info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
    var kind: UInt64 = directory ? 0o040000 : 0o100000
    if info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT > 0 {
      var tag = FILE_ATTRIBUTE_TAG_INFO()
      let size = DWORD(MemoryLayout.size(ofValue: tag))
      guard GetFileInformationByHandleEx(handle.handle, FileAttributeTagInfo,
                                         &tag, size) else {
        throw Debuggee.Error(windows: GetLastError())
      }
      if tag.ReparseTag == IO_REPARSE_TAG_SYMLINK ||
         tag.ReparseTag == IO_REPARSE_TAG_MOUNT_POINT {
        kind = 0o120000
      }
    }
    let size = UInt64(info.nFileSizeHigh) << 32 | UInt64(info.nFileSizeLow)
    let inode = UInt64(info.nFileIndexHigh) << 32 | UInt64(info.nFileIndexLow)
    let writable = info.dwFileAttributes & FILE_ATTRIBUTE_READONLY == 0
    let permissions: UInt64 = writable ? 0o700 : 0o500
    return FileStatus(device: UInt64(info.dwVolumeSerialNumber), inode: inode,
                      mode: kind | permissions,
                      links: UInt64(info.nNumberOfLinks), user: 0, group: 0,
                      special: 0, size: size, block: 0, blocks: 0,
                      access: timestamp(info.ftLastAccessTime),
                      modification: timestamp(info.ftLastWriteTime),
                      change: timestamp(info.ftCreationTime))
  }
}

@inline(never)
private func inspect(_ path: String, reparse: Bool) throws(Debuggee.Error)
    -> WindowsHandle {
  let flag = reparse ? FILE_FLAG_OPEN_REPARSE_POINT : 0
  let raw = withUTF16CString(path) { path in
    CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | flag, nil)
  }
  guard let raw else {
    throw Debuggee.Error(windows: GetLastError())
  }
  if raw == INVALID_HANDLE_VALUE {
    throw Debuggee.Error(windows: GetLastError())
  }
  return WindowsHandle(raw)
}

private func folder(_ path: String) throws(Debuggee.Error) {
  let status = withUTF16CString(path) { path in
    CreateDirectoryW(path, nil)
  }
  if status {
    return
  }
  let code = GetLastError()
  if code == ERROR_ALREADY_EXISTS {
    let metadata = try WindowsFileSystem.status(path, link: false)
    if metadata.mode & 0o170000 == 0o040000 {
      return
    }
    throw Debuggee.Error(windows: code)
  }
  guard code == ERROR_PATH_NOT_FOUND,
      let parent = try WindowsPath.parent(path) else {
    throw Debuggee.Error(windows: code)
  }
  try folder(parent)
  try folder(path)
}

extension OVERLAPPED {
  fileprivate init(offset: UInt64, append: Bool = false)
      throws(Debuggee.Error) {
    guard append || offset <= UInt64(Int64.max) else {
      throw .system(CInt(ERROR_ARITHMETIC_OVERFLOW))
    }
    let offset = append ? UInt64.max : offset
    self.init()
    Offset = DWORD(truncatingIfNeeded: offset)
    OffsetHigh = DWORD(offset >> 32)
  }
}

private func timestamp(_ value: FILETIME) -> UInt64 {
  let ticks = UInt64(value.dwHighDateTime) << 32
            | UInt64(value.dwLowDateTime)
  let seconds = ticks / 10_000_000
  return seconds >= 11_644_473_600 ? seconds - 11_644_473_600 : 0
}

#endif
