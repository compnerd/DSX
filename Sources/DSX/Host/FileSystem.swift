// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct FileIdentifier: Equatable, Sendable {
  internal let rawValue: UInt64

  internal init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

internal struct FileOptions: OptionSet, Sendable {
  internal let rawValue: UInt8

  internal init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  internal static let append = FileOptions(rawValue: 0x01)
  internal static let create = FileOptions(rawValue: 0x02)
  internal static let exclusive = FileOptions(rawValue: 0x20)
  internal static let read = FileOptions(rawValue: 0x04)
  internal static let truncate = FileOptions(rawValue: 0x08)
  internal static let write = FileOptions(rawValue: 0x10)
}

internal struct FileStatus: Sendable {
  internal let device: UInt64
  internal let inode: UInt64
  internal let mode: UInt64
  internal let links: UInt64
  internal let user: UInt64
  internal let group: UInt64
  internal let special: UInt64
  internal let size: UInt64
  internal let block: UInt64
  internal let blocks: UInt64
  internal let access: UInt64
  internal let modification: UInt64
  internal let change: UInt64
}

internal struct FileSystem: ~Copyable, Sendable {
  private var handles: Array<NativeFileSystem.Handle?>
  private var root: String?

  internal init() {
    handles = []
    root = nil
  }

  deinit {
    for handle in handles {
      if let handle {
        try? NativeFileSystem.close(handle)
      }
    }
  }

  internal mutating func open(_ path: String, working: String? = nil,
                              options: FileOptions, mode: UInt32)
      throws(Debuggee.Error) -> FileIdentifier {
    let path = try resolve(path, working: working)
    let handle = try NativeFileSystem.open(path, options: options, mode: mode)
    for index in handles.indices where handles[index] == nil {
      handles[index] = handle
      return FileIdentifier(rawValue: UInt64(index + 1))
    }
    handles.append(handle)
    return FileIdentifier(rawValue: UInt64(handles.count))
  }

  internal mutating func close(_ file: FileIdentifier) throws(Debuggee.Error) {
    guard let index = index(file), let handle = handles[index] else {
      throw .file(.descriptor)
    }
    handles[index] = nil
    try NativeFileSystem.close(handle)
  }

  internal mutating func read(_ file: FileIdentifier, offset: UInt64, size: Int,
                              into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .file(.invalid)
    }
    guard let handle = handle(file) else {
      throw .file(.descriptor)
    }
    let count = min(size, output.freeCapacity)
    try NativeFileSystem.read(handle, offset: offset, size: count,
                              into: &output)
  }

  internal mutating func write(_ file: FileIdentifier, offset: UInt64,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    guard let handle = handle(file) else {
      throw .file(.descriptor)
    }
    return try NativeFileSystem.write(handle, offset: offset, bytes: bytes)
  }

  internal borrowing func size(_ file: FileIdentifier) throws(Debuggee.Error)
      -> UInt64 {
    guard let handle = handle(file) else {
      throw .file(.descriptor)
    }
    return try NativeFileSystem.size(handle)
  }

  internal borrowing func status(_ file: FileIdentifier) throws(Debuggee.Error)
      -> FileStatus {
    guard let handle = handle(file) else {
      throw .file(.descriptor)
    }
    return try NativeFileSystem.status(handle)
  }

  internal borrowing func status(_ path: String, working: String?, link: Bool)
      throws(Debuggee.Error) -> FileStatus {
    let path = try resolve(path, working: working)
    return try NativeFileSystem.status(path, link: link)
  }

  internal borrowing func destination(_ path: String, working: String?)
      throws(Debuggee.Error) -> String {
    try NativeFileSystem.destination(resolve(path, working: working))
  }

  internal borrowing func remove(_ path: String, working: String?)
      throws(Debuggee.Error) {
    let path = try resolve(path, working: working)
    try NativeFileSystem.remove(path)
  }

  internal borrowing func link(_ target: String, at path: String,
                               working: String?) throws(Debuggee.Error) {
    let path = try resolve(path, working: working)
    try NativeFileSystem.link(target, at: path)
  }

  internal borrowing func size(_ path: String, working: String?)
      throws(Debuggee.Error) -> UInt64 {
    try NativeFileSystem.size(resolve(path, working: working))
  }

  internal mutating func clear() throws(Debuggee.Error) {
    var failure: Debuggee.Error?
    for index in handles.indices {
      guard let handle = handles[index] else {
        continue
      }
      handles[index] = nil
      do {
        try NativeFileSystem.close(handle)
      } catch {
        if failure == nil {
          failure = error
        }
      }
    }
    if let failure {
      throw failure
    }
  }

  internal mutating func select(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    root = try NativeFileSystem.root(process)
  }

  internal borrowing func resolve(_ path: String, working: String?)
      throws(Debuggee.Error) -> String {
    let path = try NativeFileSystem.resolve(path, working: working)
    return try NativeFileSystem.scope(path, root: root)
  }

  private borrowing func handle(_ file: FileIdentifier)
      -> NativeFileSystem.Handle? {
    guard let index = index(file) else {
      return nil
    }
    return handles[index]
  }

  private borrowing func index(_ file: FileIdentifier) -> Int? {
    guard file.rawValue > 0, file.rawValue <= UInt64(Int.max) else {
      return nil
    }
    let index = Int(file.rawValue - 1)
    guard index < handles.count else {
      return nil
    }
    return index
  }
}
