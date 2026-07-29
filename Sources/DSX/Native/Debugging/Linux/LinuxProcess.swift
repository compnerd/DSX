// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal struct LinuxProcessCursor: ~Copyable, @unchecked Sendable {
  private let directory: OpaquePointer

  internal init() throws(Debuggee.Error) {
    guard let directory = opendir("/proc") else {
      throw LinuxProcFS.failure(errno)
    }
    self.directory = directory
  }

  deinit {
    _ = closedir(directory)
  }

  internal mutating func next() throws(Debuggee.Error)
      -> Debuggee.Process.Info? {
    while let entry = readdir(directory) {
      var name = entry.pointee.d_name
      let identifier = withUnsafePointer(to: &name) { name in
        name.withMemoryRebound(to: CChar.self, capacity: 1) { name in
          decimal(name)
        }
      }
      if let identifier, identifier > 0 {
        let process = ProcessIdentifier(rawValue: identifier)
        return try process.info
      }
    }
    return nil
  }
}

extension ProcessIdentifier {
  internal var info: Debuggee.Process.Info {
    get throws(Debuggee.Error) {
      let identifier = try native
      return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 4096,
                                               { data throws(Debuggee.Error) in
        var output = OutputSpan(buffer: data, initializedCount: 0)
        try LinuxProcFS.read("/proc/\(identifier)/stat", into: &output)
        let bytes = output.span
        var close: Int?
        for index in 0 ..< bytes.count where bytes[index] == UInt8(ascii: ")") {
          close = index
        }
        guard let close, close + 4 < bytes.count else {
          throw .process
        }
        let tail = bytes.extracting((close + 4)...)
        guard let ancestor = decimal(tail) else {
          throw .process
        }
        let name = try LinuxProcFS.link("/proc/\(identifier)/exe")
        let arguments = try arguments
        let parent: ProcessIdentifier? = if ancestor > 0 {
          ProcessIdentifier(rawValue: ancestor)
        } else {
          nil
        }
        let architecture = try machine
        return Debuggee.Process.Info(process: self, parent: parent, name: name,
                                     arguments: arguments,
                                     architecture: architecture)
      })
    }
  }

  private var arguments: Array<String> {
    get throws(Debuggee.Error) {
      let bytes = try command
      var arguments = Array<String>()
      var start = 0
      for end in bytes.indices where bytes[end] == 0 {
        arguments.append(String(decoding: bytes[start ..< end], as: UTF8.self))
        start = end + 1
      }
      if start < bytes.count {
        arguments.append(String(decoding: bytes[start...], as: UTF8.self))
      }
      return arguments
    }
  }

  private var command: Array<UInt8> {
    get throws(Debuggee.Error) {
      do {
        return try LinuxProcFS.contents("/proc/\(native)/cmdline")
      } catch .access, .process {
        return []
      } catch {
        throw error
      }
    }
  }

  private var machine: String {
    get throws(Debuggee.Error) {
      let identifier = try native
      return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 64,
                                               { data throws(Debuggee.Error) in
        var output = OutputSpan(buffer: data, initializedCount: 0)
        try LinuxProcFS.read("/proc/\(identifier)/exe", into: &output)
        guard let module = try ELFModule(output.span) else {
          throw .process
        }
        return (try? module.architecture) ?? "unknown"
      })
    }
  }

}

#endif
