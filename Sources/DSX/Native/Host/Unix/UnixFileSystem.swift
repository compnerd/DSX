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
  internal static let separator = UInt8(ascii: "/")

  internal typealias Handle = CInt
#if os(Android) || os(Linux)
  internal typealias Root = LinuxFileRoot
#else
  internal typealias Root = Never
#endif
  private typealias Failure = Debuggee.Error

  internal static func canonical(_ path: String) throws(Debuggee.Error)
      -> String {
    try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(PATH_MAX),
                                      { buffer throws(Failure) in
      let value = path.withCString { path in
        realpath(path, buffer.baseAddress)
      }
      guard let value else {
        throw Debuggee.Error(filesystem: errno)
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
      throw Debuggee.Error(filesystem: errno)
    }
    defer {
      _ = closedir(handle)
    }
    var completions = Array<String>()
    while true {
      errno = 0
      guard let entry = readdir(handle) else {
        guard errno == 0 else {
          throw Debuggee.Error(filesystem: errno)
        }
        break
      }
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
      let directory = folder(candidate)
      if directories {
        guard directory else {
          continue
        }
      }
      completions.append(directory ? candidate + "/" : candidate)
    }
    completions.order(by: <)
    return completions
  }

  internal static func resolve(_ path: String, directory: String?)
      throws(Debuggee.Error) -> String {
    guard let directory else {
      return path
    }
    if path.first == "/" {
      return path
    }
    let separator = directory.hasSuffix("/") ? "" : "/"
    return directory + separator + path
  }

  internal static func root(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Root? {
    guard process.rawValue > 0 else {
      return nil
    }
#if os(Android) || os(Linux)
    return try LinuxFileRoot(process)
#else
    throw .system(ENOTSUP)
#endif
  }

  internal static func open(_ path: String, options: FileOptions, mode: UInt32,
                            root: borrowing Root? = nil) throws(Debuggee.Error)
      -> CInt {
    guard let mode = mode_t(exactly: mode) else {
      throw .file(.invalid)
    }
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
#if os(Android) || os(Linux)
    switch root {
    case .some(let root):
      return try root.open(path, flags: flags, mode: mode)
    case .none:
      break
    }
#endif
    let handle = path.withCString { path in
      DSX::open(path, flags | O_CLOEXEC, mode)
    }
    guard handle >= 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
    return handle
  }

  internal static func close(_ handle: CInt) throws(Debuggee.Error) {
    guard DSX::close(handle) == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  internal static func read(_ handle: CInt, offset: UInt64, size: Int,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard offset <= UInt64(off_t.max) else {
      throw .system(EOVERFLOW)
    }
    try output.withUnsafeMutableBufferPointer { data, index throws(Failure) in
      guard let base = data.baseAddress else {
        return
      }
      let count = min(size, data.count - index)
      while true {
        let result =
            pread(handle, base.advanced(by: index), count, off_t(offset))
        if result >= 0 {
          index += result
          return
        }
        guard errno == EINTR else {
          throw Debuggee.Error(filesystem: errno)
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
            throw Debuggee.Error(filesystem: errno)
          }
        }
      }
    }
  }

  internal static func remove(_ path: String, root: borrowing Root? = nil)
      throws(Debuggee.Error) {
#if os(Android) || os(Linux)
    switch root {
    case .some(let root):
      let location = try LinuxFileLocation(path, root: root)
      return try location.remove()
    case .none:
      break
    }
#endif
    let status = path.withCString { path in
      unlink(path)
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  internal static func link(_ target: String, at path: String,
                            root: borrowing Root? = nil)
      throws(Debuggee.Error) {
#if os(Android) || os(Linux)
    switch root {
    case .some(let root):
      let location = try LinuxFileLocation(path, root: root)
      return try location.link(target)
    case .none:
      break
    }
#endif
    let status = target.withCString { target in
      path.withCString { path in
        DSX::symlink(target, path)
      }
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  internal static func permissions(_ path: String, mode: UInt32)
      throws(Debuggee.Error) {
    let status = path.withCString { path in
      chmod(path, mode_t(truncatingIfNeeded: mode))
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
  }

  internal static func size(_ path: String, root: borrowing Root? = nil)
      throws(Debuggee.Error) -> UInt64 {
#if os(Android) || os(Linux)
    switch root {
    case .some(let root):
      let handle = try root.open(path, flags: O_PATH)
      defer { _ = DSX::close(handle) }
      return try size(handle)
    case .none:
      break
    }
#endif
    var metadata = stat()
    let status = path.withCString { path in
      stat(path, &metadata)
    }
    guard status == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
    guard metadata.st_size >= 0 else {
      throw .state
    }
    return UInt64(metadata.st_size)
  }

  internal static func size(_ handle: CInt) throws(Debuggee.Error) -> UInt64 {
    var metadata = stat()
    guard fstat(handle, &metadata) == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
    guard metadata.st_size >= 0 else {
      throw .state
    }
    return UInt64(metadata.st_size)
  }

  internal static func status(_ path: String, link: Bool,
                              root: borrowing Root? = nil)
      throws(Debuggee.Error) -> FileStatus {
#if os(Android) || os(Linux)
    switch root {
    case .some(let root):
      let flags = O_PATH | (link ? O_NOFOLLOW : 0)
      let handle = try root.open(path, flags: flags)
      defer { _ = DSX::close(handle) }
      return try status(handle)
    case .none:
      break
    }
#endif
    var metadata = stat()
    let result = path.withCString { path in
      link ? lstat(path, &metadata) : stat(path, &metadata)
    }
    guard result == 0 else {
      throw Debuggee.Error(filesystem: errno)
    }
    return FileStatus(metadata)
  }

  internal static func destination(_ path: String, root: borrowing Root? = nil)
      throws(Debuggee.Error) -> String {
#if os(Android) || os(Linux)
    let handle = try root?.open(path, flags: O_PATH | O_NOFOLLOW)
    defer {
      if let handle { _ = DSX::close(handle) }
    }
#endif
    let capacity = Configuration.FileSystem.Capacity
    return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: capacity,
                                             { buffer throws(Debuggee.Error) in
      guard let base = buffer.baseAddress else {
        throw .state
      }
      let count = path.withCString { path in
#if os(Android) || os(Linux)
        if let handle {
          return readlinkat(handle, "", base, buffer.count)
        }
#endif
        return readlink(path, base, buffer.count)
      }
      guard count >= 0 else {
        throw Debuggee.Error(filesystem: errno)
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
      throw Debuggee.Error(filesystem: errno)
    }
    return FileStatus(metadata)
  }

  private static func folder(_ path: String) -> Bool {
    var metadata = stat()
    let result = path.withCString { path in
      stat(path, &metadata)
    }
    guard result == 0 else {
      return false
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
    throw Debuggee.Error(filesystem: code)
  }
}

extension FileStatus {
  fileprivate init(_ value: stat) {
    let times = timestamps(value)
    self.init(device: UInt64(clamping: value.st_dev),
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
}

extension UnixFileSystem {
  internal static func separates(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "/")
  }

  internal static func matches(_ path: borrowing Span<UInt8>, _ value: String,
                               component: Bool) -> Bool {
    let value = value.utf8Span.span
    let lhs = component ? path.basename : 0 ..< path.count
    let rhs = component ? value.basename : 0 ..< value.count
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

#endif
