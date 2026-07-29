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

  @inline(never)
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

  @inline(never)
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

  @inline(never)
  internal static func status(_ path: String, link: Bool) throws(Debuggee.Error)
      -> FileStatus {
    let handle = try inspect(path, reparse: link)
    let file =
        WindowsFileHandle(raw: UInt(bitPattern: handle.value), append: false)
    return try status(file)
  }

  internal static func destination(_ path: String) throws(Debuggee.Error)
      -> String {
    let handle = try inspect(path, reparse: true)
    let capacity = Int(MAXIMUM_REPARSE_DATA_BUFFER_SIZE)
    return try withUnsafeTemporaryAllocation(byteCount: capacity, alignment: 4,
                                             { bytes throws(Failure) in
      var count: DWORD = 0
      let status = DeviceIoControl(handle.value, FSCTL_GET_REPARSE_POINT, nil,
                                   0, bytes.baseAddress, DWORD(capacity),
                                   &count, nil)
      guard status else {
        throw WindowsError.debuggee(GetLastError())
      }
      let buffer = UnsafeRawBufferPointer(rebasing: bytes[..<Int(count)])
      return try reparse(buffer)
    })
  }

  internal static func status(_ handle: WindowsFileHandle)
      throws(Debuggee.Error) -> FileStatus {
    var info = BY_HANDLE_FILE_INFORMATION()
    guard GetFileInformationByHandle(handle.handle, &info) else {
      throw WindowsError.debuggee(GetLastError())
    }
    let directory = info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
    var kind: UInt64 = directory ? 0o040000 : 0o100000
    if info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT > 0 {
      var tag = FILE_ATTRIBUTE_TAG_INFO()
      let size = DWORD(MemoryLayout.size(ofValue: tag))
      guard GetFileInformationByHandleEx(handle.handle, FileAttributeTagInfo,
                                         &tag, size) else {
        throw WindowsError.debuggee(GetLastError())
      }
      if tag.ReparseTag == IO_REPARSE_TAG_SYMLINK ||
         tag.ReparseTag == IO_REPARSE_TAG_MOUNT_POINT {
        kind = 0o120000
      }
    }
    let size = UInt64(info.nFileSizeHigh) << 32 | UInt64(info.nFileSizeLow)
    let inode = UInt64(info.nFileIndexHigh) << 32 | UInt64(info.nFileIndexLow)
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
    guard lhs.count == rhs.count else {
      return false
    }
    for index in 0 ..< lhs.count {
      let source = path[lhs.lowerBound + index]
      let candidate = value[rhs.lowerBound + index]
      if separates(source), separates(candidate) {
        continue
      }
      guard lowercase(source) == lowercase(candidate) else {
        return false
      }
    }
    return true
  }
}

private func basename(_ path: borrowing Span<UInt8>) -> Range<Int> {
  var start = 0
  for index in 0 ..< path.count where separates(path[index]) {
    start = index + 1
  }
  return start ..< path.count
}

private func lowercase(_ byte: UInt8) -> UInt8 {
  byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
      ? byte + UInt8(ascii: "a") - UInt8(ascii: "A") : byte
}

private func separates(_ byte: UInt8) -> Bool {
  byte == UInt8(ascii: "/") || byte == UInt8(ascii: "\\")
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

@inline(never)
private func inspect(_ path: String, reparse: Bool) throws(Debuggee.Error)
    -> WindowsHandle {
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
  return WindowsHandle(raw)
}

private func reparse(_ bytes: UnsafeRawBufferPointer)
    throws(Debuggee.Error) -> String {
  let header = MemoryLayout<dsx_reparse_names>.size
  guard bytes.count >= header else {
    throw WindowsError.debuggee(ERROR_INVALID_REPARSE_DATA)
  }
  let names = bytes.loadUnaligned(as: dsx_reparse_names.self)
  let start: Int = switch names.ReparseTag {
  case IO_REPARSE_TAG_SYMLINK: header + MemoryLayout<ULONG>.size
  case IO_REPARSE_TAG_MOUNT_POINT: header
  default: throw WindowsError.debuggee(ERROR_NOT_A_REPARSE_POINT)
  }
  let fixed = MemoryLayout<ULONG>.size + 2 * MemoryLayout<USHORT>.size
  let extent = fixed + Int(names.ReparseDataLength)
  let offset = Int(names.SubstituteNameOffset)
  let length = Int(names.SubstituteNameLength)
  guard extent <= bytes.count, start <= extent, offset <= extent - start,
      length <= extent - start - offset, offset % 2 == 0, length % 2 == 0 else {
    throw WindowsError.debuggee(ERROR_INVALID_REPARSE_DATA)
  }
  let begin = start + offset
  let buffer = UnsafeRawBufferPointer(rebasing: bytes[begin ..< begin + length])
  let value = buffer.bindMemory(to: WCHAR.self)
  let relative = names.ReparseTag == IO_REPARSE_TAG_SYMLINK &&
      bytes.loadUnaligned(fromByteOffset: header, as: ULONG.self) & 1 != 0
  // UTF-16 "\??\" identifies an NT DOS-device path. "\??\UNC\" needs two
  // leading separators after removing the device prefix.
  let separator: WCHAR = 0x005c
  let question: WCHAR = 0x003f
  var skipped = 0
  var prefix = ""
  if relative == false, value.count >= 4, value[0] == separator,
      value[1] == question, value[2] == question, value[3] == separator {
    skipped = 4
    let network = value.count >= 8 && value[4] == 0x0055 &&
        value[5] == 0x004e && value[6] == 0x0043 && value[7] == separator
    let drive = value.count >= 6 && value[5] == 0x003a
    switch (network, drive) {
    case (true, _):
      skipped = 8
      prefix = #"\\"#
    case (false, true):
      break
    case (false, false):
      // Volume GUIDs and other device paths retain Win32's extended prefix.
      prefix = #"\\?\"#
    }
  }
  let path = UnsafeBufferPointer(rebasing: value[skipped...])
  let result = String(decoding: path, as: UTF16.self)
  return prefix.isEmpty ? result : prefix + result
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
    throw WindowsError.debuggee(code)
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
