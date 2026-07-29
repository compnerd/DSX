// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsFileHandle: Sendable {
  fileprivate let raw: UInt
  fileprivate let append: Bool

  fileprivate var handle: HANDLE {
    HANDLE(bitPattern: raw)!
  }
}

internal enum WindowsFileSystem {
  internal typealias Handle = WindowsFileHandle
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
    let path = try WindowsPath.canonical(path)
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
      throw WindowsError.debuggee(code)
    }
    if handle == INVALID_HANDLE_VALUE {
      let code = GetLastError()
      if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND {
        return []
      }
      throw WindowsError.debuggee(code)
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
                                                 trailing: directories))
    } while FindNextFileW(handle, &data)
    let code = GetLastError()
    guard code == ERROR_NO_MORE_FILES else {
      throw WindowsError.debuggee(code)
    }
    completions.order(by: <)
    return completions
  }

  internal static func resolve(_ path: String, working: String?)
      throws(Debuggee.Error) -> String {
    if let working {
      try WindowsPath.combine(working, path)
    } else {
      try WindowsPath.canonical(path)
    }
  }

  internal static func root(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> String? {
    _ = process
    return nil
  }

  internal static func scope(_ path: String, root: String?)
      throws(Debuggee.Error) -> String {
    _ = root
    return path
  }

  internal static func open(_ path: String, options: FileOptions, mode: UInt32)
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
      throw WindowsError.debuggee(GetLastError())
    }
    return WindowsFileHandle(raw: UInt(bitPattern: handle),
                             append: options.contains(.append))
  }

  internal static func close(_ handle: WindowsFileHandle)
      throws(Debuggee.Error) {
    guard CloseHandle(handle.handle) else {
      throw WindowsError.debuggee(GetLastError())
    }
  }

  internal static func read(_ handle: WindowsFileHandle, offset: UInt64,
                            size: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    try position(handle.handle, offset: offset)
    try output.withUnsafeMutableBufferPointer { data, offset throws(Failure) in
      let available = min(size, data.count - offset)
      let requested = DWORD(clamping: available)
      var count: DWORD = 0
      let status =
          ReadFile(handle.handle, data.baseAddress!.advanced(by: offset),
                   requested, &count, nil)
      guard status else {
        throw WindowsError.debuggee(GetLastError())
      }
      offset += Int(count)
    }
  }

  internal static func write(_ handle: WindowsFileHandle, offset: UInt64,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    if handle.append {
      try position(handle.handle, distance: 0, origin: FILE_END)
    } else {
      try position(handle.handle, offset: offset)
    }
    return try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      var count: DWORD = 0
      let requested = DWORD(clamping: bytes.count)
      let status =
          WriteFile(handle.handle, bytes.baseAddress, requested, &count, nil)
      guard status else {
        throw WindowsError.debuggee(GetLastError())
      }
      return Int(count)
    }
  }

  internal static func remove(_ path: String) throws(Debuggee.Error) {
    let status = withUTF16CString(path) { path in
      DeleteFileW(path)
    }
    guard status else {
      throw WindowsError.debuggee(GetLastError())
    }
  }

  internal static func link(_ target: String, at path: String)
      throws(Debuggee.Error) {
    var flags = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
    while true {
      let status = withUTF16CString(target) { target in
        withUTF16CString(path) { path in
          CreateSymbolicLinkW(path, target, flags) == 0 ? false : true
        }
      }
      if status {
        return
      }
      let code = GetLastError()
      if code == ERROR_DIRECTORY, flags & SYMBOLIC_LINK_FLAG_DIRECTORY == 0 {
        flags |= SYMBOLIC_LINK_FLAG_DIRECTORY
        continue
      }
      if code == ERROR_INVALID_PARAMETER,
          flags & SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE > 0 {
        flags &= ~SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
        continue
      }
      throw WindowsError.debuggee(code)
    }
  }

  internal static func permissions(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    _ = mode
    _ = try status(path, link: false)
  }

  internal static func size(_ path: String) throws(Debuggee.Error) -> UInt64 {
    var metadata = WIN32_FILE_ATTRIBUTE_DATA()
    let status = withUTF16CString(path) { path in
      GetFileAttributesExW(path, GetFileExInfoStandard, &metadata)
    }
    guard status else {
      throw WindowsError.debuggee(GetLastError())
    }
    let high = UInt64(metadata.nFileSizeHigh) << 32
    let low = UInt64(metadata.nFileSizeLow)
    return high | low
  }

  internal static func size(_ handle: WindowsFileHandle) throws(Debuggee.Error)
      -> UInt64 {
    var value = LARGE_INTEGER()
    guard GetFileSizeEx(handle.handle, &value), value.QuadPart >= 0 else {
      throw WindowsError.debuggee(GetLastError())
    }
    return UInt64(value.QuadPart)
  }

  internal static func status(_ path: String, link: Bool) throws(Debuggee.Error)
      -> FileStatus {
    try inspect(path, reparse: link)
  }

  internal static func destination(_ path: String) throws(Debuggee.Error)
      -> String {
    let raw = withUTF16CString(path) { path in
      CreateFileW(path, 0,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nil,
                  OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nil)
    }
    guard let raw else {
      throw WindowsError.debuggee(GetLastError())
    }
    if raw == INVALID_HANDLE_VALUE {
      throw WindowsError.debuggee(GetLastError())
    }
    let handle = WindowsHandle(raw)
    return try WindowsPath.resolve(handle.value)
  }

  internal static func status(_ handle: WindowsFileHandle)
      throws(Debuggee.Error) -> FileStatus {
    var info = BY_HANDLE_FILE_INFORMATION()
    guard GetFileInformationByHandle(handle.handle, &info) else {
      throw WindowsError.debuggee(GetLastError())
    }
    let directory = info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
    let kind: UInt64 = directory ? 0o040000 : 0o100000
    let size = UInt64(info.nFileSizeHigh) << 32
             | UInt64(info.nFileSizeLow)
    let inode = UInt64(info.nFileIndexHigh) << 32
              | UInt64(info.nFileIndexLow)
    return FileStatus(device: UInt64(info.dwVolumeSerialNumber), inode: inode,
                      mode: kind | 0o700, links: UInt64(info.nNumberOfLinks),
                      user: 0, group: 0, special: 0, size: size, block: 0,
                      blocks: 0, access: timestamp(info.ftLastAccessTime),
                      modification: timestamp(info.ftLastWriteTime),
                      change: timestamp(info.ftCreationTime))
  }
}

extension WindowsFileSystem {
  internal static func matches(_ path: borrowing Span<UInt8>, _ value: String,
                               component: Bool) -> Bool {
    let value = value.utf8Span.span
    let lhs = component ? basename(path) : 0 ..< path.count
    let rhs = component ? basename(value) : 0 ..< value.count
    if unicode(path, range: lhs) || unicode(value, range: rhs) {
      let source = String(decoding: path.extracting(lhs), as: UTF8.self)
      let candidate = String(decoding: value.extracting(rhs), as: UTF8.self)
      return normalize(source) == normalize(candidate)
    }
    return equivalent(path.extracting(lhs), value.extracting(rhs))
  }
}

private func normalize(_ path: borrowing String) -> String {
  var normalized = String()
  normalized.reserveCapacity(path.utf8.count)
  for character in path.lowercased() {
    normalized.append(character == "\\" ? "/" : character)
  }
  return normalized
}

private func unicode(_ path: borrowing Span<UInt8>, range: Range<Int>) -> Bool {
  for index in range where path[index] >= 0x80 {
    return true
  }
  return false
}

private func inspect(_ path: String, reparse: Bool) throws(Debuggee.Error)
    -> FileStatus {
  let flag = reparse ? FILE_FLAG_OPEN_REPARSE_POINT : 0
  let raw = withUTF16CString(path) { path in
    CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | flag, nil)
  }
  guard let raw else {
    throw WindowsError.debuggee(GetLastError())
  }
  if raw == INVALID_HANDLE_VALUE {
    throw WindowsError.debuggee(GetLastError())
  }
  let handle = WindowsHandle(raw)
  let file =
      WindowsFileHandle(raw: UInt(bitPattern: handle.value), append: false)
  return try WindowsFileSystem.status(file)
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
    return
  }
  guard code == ERROR_PATH_NOT_FOUND,
      let parent = try WindowsPath.parent(path) else {
    throw WindowsError.debuggee(code)
  }
  try folder(parent)
  try folder(path)
}

private func position(_ handle: HANDLE, offset: UInt64) throws(Debuggee.Error) {
  guard offset <= UInt64(Int64.max) else {
    throw .system(CInt(ERROR_ARITHMETIC_OVERFLOW))
  }
  try position(handle, distance: Int64(offset), origin: FILE_BEGIN)
}

private func position(_ handle: HANDLE, distance: Int64, origin: DWORD)
    throws(Debuggee.Error) {
  let position = LARGE_INTEGER(QuadPart: distance)
  guard SetFilePointerEx(handle, position, nil, origin) else {
    throw WindowsError.debuggee(GetLastError())
  }
}

private func timestamp(_ value: FILETIME) -> UInt64 {
  let ticks = UInt64(value.dwHighDateTime) << 32
            | UInt64(value.dwLowDateTime)
  let seconds = ticks / 10_000_000
  return seconds >= 11_644_473_600 ? seconds - 11_644_473_600 : 0
}

#endif
