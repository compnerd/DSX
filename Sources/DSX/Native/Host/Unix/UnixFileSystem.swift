// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal enum UnixFileSystem {
  internal typealias Handle = CInt
  private typealias Failure = Debuggee.Error

  internal static func canonical(_ path: String) throws(Debuggee.Error)
      -> String {
    try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(PATH_MAX),
                                      { buffer throws(Failure) in
      let value = path.withCString { path in
        realpath(path, buffer.baseAddress)
      }
      guard let value else {
        throw UnixError.filesystem(errno)
      }
      return String(cString: value)
    })
  }

  internal static func create(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    guard !path.isEmpty else {
      throw .system(EINVAL)
    }
    var index = path.startIndex
    while index < path.endIndex {
      if path[index] == "/", index != path.startIndex {
        try directory(String(path[..<index]), mode: mode)
      }
      path.formIndex(after: &index)
    }
    try directory(path, mode: mode)
  }

  internal static func complete(_ path: String, directories: Bool)
      throws(Debuggee.Error) -> Array<String> {
    let separator = path.lastIndex(of: "/")
    let components: (String, Substring) = if let separator {
      (String(path[...separator]), path[path.index(after: separator)...])
    } else {
      ("", path[...])
    }
    let (base, prefix) = components
    let directory = base.isEmpty ? "." : base
    guard let handle = directory.withCString({ path in opendir(path) }) else {
      throw UnixError.filesystem(errno)
    }
    defer {
      _ = closedir(handle)
    }
    var completions = Array<String>()
    while let entry = readdir(handle) {
      var field = entry.pointee.d_name
      let name = withUnsafePointer(to: &field) { field in
        field.withMemoryRebound(to: CChar.self, capacity: 1) { field in
          String(cString: field)
        }
      }
      if name == "." || name == ".." {
        continue
      }
      guard name.hasPrefix(prefix) else {
        continue
      }
      let candidate = base + name
      if directories {
        guard try folder(candidate) else {
          continue
        }
        completions.append(candidate + "/")
      } else {
        completions.append(candidate)
      }
    }
    completions.order(by: <)
    return completions
  }

  internal static func resolve(_ path: String, working: String?)
      throws(Debuggee.Error) -> String {
    guard let working else {
      return path
    }
    if path.first == "/" {
      return path
    }
    let separator = working.hasSuffix("/") ? "" : "/"
    return working + separator + path
  }

  internal static func root(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> String? {
    guard process.rawValue > 0 else {
      return nil
    }
#if os(Android) || os(Linux)
    guard process.rawValue <= UInt64(pid_t.max) else {
      throw .process
    }
    let root = "/proc/\(process.rawValue)/root"
    _ = try status(root, link: false)
    return root
#else
    throw .system(ENOTSUP)
#endif
  }

  internal static func scope(_ path: String, root: String?)
      throws(Debuggee.Error) -> String {
    guard let root else {
      return path
    }
    return if path.first == "/" {
      root + path
    } else {
      root + "/" + path
    }
  }

  internal static func open(_ path: String, options: FileOptions, mode: UInt32)
      throws(Debuggee.Error) -> CInt {
    var flags = switch (options.contains(.read), options.contains(.write)) {
    case (true, true): O_RDWR
    case (true, false): O_RDONLY
    case (false, true): O_WRONLY
    case (false, false): O_RDONLY
    }
    if options.contains(.append) {
      flags |= O_APPEND
    }
    if options.contains(.create) {
      flags |= O_CREAT
    }
    if options.contains(.truncate) {
      flags |= O_TRUNC
    }
    if options.contains(.exclusive) {
      flags |= O_EXCL
    }
    let handle = path.withCString { path in
      DSX::open(path, flags | O_CLOEXEC, mode_t(mode))
    }
    guard handle >= 0 else {
      throw UnixError.filesystem(errno)
    }
    return handle
  }

  internal static func close(_ handle: CInt) throws(Debuggee.Error) {
    guard DSX::close(handle) == 0 else {
      throw UnixError.filesystem(errno)
    }
  }

  internal static func read(_ handle: CInt, offset: UInt64, size: Int,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard offset <= UInt64(off_t.max) else {
      throw .system(EOVERFLOW)
    }
    try output.withUnsafeMutableBufferPointer { data, index throws(Failure) in
      let count = min(size, data.count - index)
      while true {
        let base = data.baseAddress!.advanced(by: index)
        let result = pread(handle, base, count, off_t(offset))
        if result >= 0 {
          index += result
          return
        }
        guard errno == EINTR else {
          throw UnixError.filesystem(errno)
        }
      }
    }
  }

  internal static func write(_ handle: CInt, offset: UInt64,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    guard offset <= UInt64(off_t.max) else {
      throw .system(EOVERFLOW)
    }
    return if bytes.isEmpty {
      0
    } else {
      try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
        guard let base = bytes.baseAddress else {
          throw .system(ENOMEM)
        }
        while true {
          let result = pwrite(handle, base, bytes.count, off_t(offset))
          if result >= 0 {
            return result
          }
          guard errno == EINTR else {
            throw UnixError.filesystem(errno)
          }
        }
      }
    }
  }

  internal static func remove(_ path: String) throws(Debuggee.Error) {
    let status = path.withCString { path in
      unlink(path)
    }
    guard status == 0 else {
      throw UnixError.filesystem(errno)
    }
  }

  internal static func link(_ target: String, at path: String)
      throws(Debuggee.Error) {
    let status = target.withCString { target in
      path.withCString { path in
        DSX::symlink(target, path)
      }
    }
    guard status == 0 else {
      throw UnixError.filesystem(errno)
    }
  }

  internal static func permissions(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    let status = path.withCString { path in
      chmod(path, mode_t(truncatingIfNeeded: mode))
    }
    guard status == 0 else {
      throw UnixError.filesystem(errno)
    }
  }

  internal static func size(_ path: String) throws(Debuggee.Error) -> UInt64 {
    var metadata = stat()
    let status = path.withCString { path in
      lstat(path, &metadata)
    }
    guard status == 0 else {
      throw UnixError.filesystem(errno)
    }
    guard metadata.st_size >= 0 else {
      throw .state
    }
    return UInt64(metadata.st_size)
  }

  internal static func size(_ handle: CInt) throws(Debuggee.Error) -> UInt64 {
    var metadata = stat()
    guard fstat(handle, &metadata) == 0 else {
      throw UnixError.filesystem(errno)
    }
    guard metadata.st_size >= 0 else {
      throw .state
    }
    return UInt64(metadata.st_size)
  }

  internal static func status(_ path: String, link: Bool) throws(Debuggee.Error)
      -> FileStatus {
    var metadata = stat()
    let result = path.withCString { path in
      link ? lstat(path, &metadata) : stat(path, &metadata)
    }
    guard result == 0 else {
      throw UnixError.filesystem(errno)
    }
    return status(metadata)
  }

  internal static func destination(_ path: String) throws(Debuggee.Error)
      -> String {
    let capacity = Configuration.PacketCapacity
    return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: capacity,
                                             { buffer throws(Debuggee.Error) in
      guard let base = buffer.baseAddress else {
        throw .state
      }
      let count = path.withCString { path in
        readlink(path, base, buffer.count)
      }
      guard count >= 0 else {
        throw UnixError.filesystem(errno)
      }
      guard count < buffer.count else {
        throw .system(ENAMETOOLONG)
      }
      let bytes = UnsafeRawBufferPointer(start: base, count: count)
      return String(decoding: bytes, as: UTF8.self)
    })
  }

  internal static func status(_ handle: CInt) throws(Debuggee.Error)
      -> FileStatus {
    var metadata = stat()
    guard fstat(handle, &metadata) == 0 else {
      throw UnixError.filesystem(errno)
    }
    return status(metadata)
  }

  private static func status(_ value: stat) -> FileStatus {
    let times = timestamps(value)
    return FileStatus(device: UInt64(clamping: value.st_dev),
                      inode: UInt64(clamping: value.st_ino),
                      mode: UInt64(clamping: value.st_mode),
                      links: UInt64(clamping: value.st_nlink),
                      user: UInt64(clamping: value.st_uid),
                      group: UInt64(clamping: value.st_gid),
                      special: UInt64(clamping: value.st_rdev),
                      size: UInt64(clamping: value.st_size),
                      block: UInt64(clamping: value.st_blksize),
                      blocks: UInt64(clamping: value.st_blocks),
                      access: UInt64(clamping: times.access),
                      modification: UInt64(clamping: times.modification),
                      change: UInt64(clamping: times.change))
  }

  private static func folder(_ path: String) throws(Debuggee.Error) -> Bool {
    var metadata = stat()
    let result = path.withCString { path in
      lstat(path, &metadata)
    }
    guard result == 0 else {
      throw UnixError.filesystem(errno)
    }
    let mask: UInt32 = numericCast(S_IFMT)
    let directory: UInt32 = numericCast(S_IFDIR)
    return UInt32(metadata.st_mode) & mask == directory
  }

  private static func directory(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    let status = path.withCString { path in
      mkdir(path, mode_t(truncatingIfNeeded: mode))
    }
    if status == 0 {
      return
    }
    let code = errno
    if code == EEXIST {
      let metadata = try UnixFileSystem.status(path, link: false)
      if metadata.mode & 0o170000 == 0o040000 {
        return
      }
    }
    throw UnixError.filesystem(code)
  }
}

extension UnixFileSystem {
  internal static func matches(_ path: borrowing Span<UInt8>, _ value: String,
                               component: Bool) -> Bool {
    let value = value.utf8Span.span
    let lhs = component ? basename(path) : 0 ..< path.count
    let rhs = component ? basename(value) : 0 ..< value.count
    guard lhs.count == rhs.count else {
      return false
    }
    for index in 0 ..< lhs.count {
      guard path[lhs.lowerBound + index] == value[rhs.lowerBound + index] else {
        return false
      }
    }
    return true
  }
}

private func basename(_ path: borrowing Span<UInt8>) -> Range<Int> {
  var start = 0
  for index in 0 ..< path.count where path[index] == UInt8(ascii: "/") {
    start = index + 1
  }
  return start ..< path.count
}

#endif
