// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(pid_t.max) else {
        throw .process
      }
      let path = "/proc/\(rawValue)/task"
      guard let directory = path.withCString({ path in
        opendir(path)
      }) else {
        throw UnixError.debuggee(errno, invalid: .process)
      }
      defer {
        _ = closedir(directory)
      }
      var threads = Array<ProcessThreadIdentifier>()
      while let entry = readdir(directory) {
        var name = entry.pointee.d_name
        let identifier = withUnsafePointer(to: &name) { name in
          name.withMemoryRebound(to: CChar.self, capacity: 1) { name in
            decimal(name)
          }
        }
        if let identifier, identifier > 0 {
          let thread = ThreadIdentifier(rawValue: identifier)
          let pair = ProcessThreadIdentifier(process: self, thread: thread)
          if try pair.alive {
            threads.append(pair)
          }
        }
      }
      return threads
    }
  }
}

extension ProcessThreadIdentifier {
  internal var alive: Bool {
    get throws(Debuggee.Error) {
      do {
        let state = try state
        return switch state {
        case UInt8(ascii: "X"), UInt8(ascii: "Z"): false
        default: true
        }
      } catch .process, .thread {
        return false
      } catch {
        throw error
      }
    }
  }

  private var state: UInt8 {
    get throws(Debuggee.Error) {
      let path = "/proc/\(process.rawValue)/task/\(thread.rawValue)/stat"
      return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256,
                                               { data throws(Debuggee.Error) in
        var output = OutputSpan(buffer: data, initializedCount: 0)
        try LinuxProcFS.read(path, into: &output)
        let bytes = output.span
        var close: Int?
        for index in 0 ..< bytes.count where bytes[index] == UInt8(ascii: ")") {
          close = index
        }
        guard let close, close + 2 < bytes.count else {
          throw .thread
        }
        return bytes[close + 2]
      })
    }
  }

  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      guard try alive else {
        throw .thread
      }
      let path = "/proc/\(process.rawValue)/task/\(thread.rawValue)/comm"
      return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256,
                                               { data throws(Debuggee.Error) in
        var output = OutputSpan(buffer: data, initializedCount: 0)
        try LinuxProcFS.read(path, into: &output)
        var count = output.span.count
        while count > 0 {
          let byte = output.span[count - 1]
          guard byte == 0 || byte == UInt8(ascii: "\n") else {
            break
          }
          count -= 1
        }
        let name = output.span.extracting(0 ..< count)
          .withUnsafeBytes { bytes in
            String(decoding: bytes, as: UTF8.self)
          }
        return Debuggee.Thread.Info(thread: self, name: name)
      })
    }
  }
}

#endif
