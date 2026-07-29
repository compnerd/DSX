// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension ProcessIdentifier {
  internal static func snapshot() throws(Debuggee.Error)
      -> Array<ProcessIdentifier> {
#if os(FreeBSD)
    var query = [CTL_KERN, KERN_PROC, KERN_PROC_PROC, 0]
#else
    var query = [
      CTL_KERN,
      KERN_PROC,
      KERN_PROC_ALL,
      0,
      Int32(MemoryLayout<kinfo_proc>.stride),
      0,
    ]
#endif
    var length = 0
    guard sysctl(&query, u_int(query.count), nil, &length, nil, 0) == 0 else {
      throw Debuggee.Error(unix: errno, invalid: .process)
    }
    let stride = MemoryLayout<kinfo_proc>.stride
    var records =
        Array<kinfo_proc>(repeating: kinfo_proc(), count: length / stride)
#if os(OpenBSD)
    query[5] = CInt(clamping: records.count)
#endif
    let status = records.withUnsafeMutableBytes { records in
      sysctl(&query, u_int(query.count), records.baseAddress, &length, nil, 0)
    }
    guard status == 0 else {
      throw Debuggee.Error(unix: errno, invalid: .process)
    }
    let count = length / stride
    var processes = Array<ProcessIdentifier>()
    processes.reserveCapacity(count)
    for record in records.prefix(count) {
#if os(FreeBSD)
      let identifier = record.ki_pid
#else
      let identifier = record.p_pid
#endif
      if identifier > 0 {
        processes.append(ProcessIdentifier(rawValue: UInt64(identifier)))
      }
    }
    return processes
  }

  internal var info: Debuggee.Process.Info {
    get throws(Debuggee.Error) {
      var record = try record
#if os(FreeBSD)
      let pid = record.ki_ppid
      let name = withUnsafeBytes(of: &record.ki_comm) {
        String(native: $0)
      }
#else
      let pid = record.p_ppid
      let name = withUnsafeBytes(of: &record.p_comm) {
        String(native: $0)
      }
#endif
      let parent = pid > 0 ? ProcessIdentifier(rawValue: UInt64(pid)) : nil
#if os(FreeBSD)
      let architecture = (try? machine) ?? "unknown"
#else
      let architecture = ProcessIdentifier.machine
#endif
      return Debuggee.Process.Info(process: self, parent: parent, name: name,
                                   architecture: architecture)
    }
  }

  private var record: kinfo_proc {
    get throws(Debuggee.Error) {
      let process = try native
#if os(FreeBSD)
      var query = [
        CTL_KERN,
        KERN_PROC,
        KERN_PROC_PID,
        process,
      ]
#else
      var query = [
        CTL_KERN,
        KERN_PROC,
        KERN_PROC_PID,
        process,
        Int32(MemoryLayout<kinfo_proc>.stride),
        1,
      ]
#endif
      var record = kinfo_proc()
      var length = MemoryLayout<kinfo_proc>.stride
      let status = withUnsafeMutablePointer(to: &record) { record in
        sysctl(&query, u_int(query.count), record, &length, nil, 0)
      }
      guard status == 0 else {
        throw Debuggee.Error(unix: errno, invalid: .process)
      }
      guard length >= MemoryLayout<kinfo_proc>.stride else {
        throw .process
      }
      return record
    }
  }

#if os(FreeBSD)
  private var machine: String {
    get throws(Debuggee.Error) {
      var query = try [CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, native]
      var path = Array<CChar>(repeating: 0, count: Int(PATH_MAX))
      var length = path.count
      let status = sysctl(&query, u_int(query.count), &path, &length, nil, 0)
      guard status == 0 else {
        throw Debuggee.Error(unix: errno, invalid: .process)
      }
      guard length > 0, length <= path.count else {
        throw .process
      }
      let name = path.withUnsafeBytes { String(native: $0) }
      let handle = try NativeFileSystem.open(name, options: [.read], mode: 0)
      defer { try? NativeFileSystem.close(handle) }
      return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 64,
                                               { bytes throws(Debuggee.Error) in
        var output = OutputSpan(buffer: bytes, initializedCount: 0)
        try NativeFileSystem.read(handle, offset: 0, size: bytes.count,
                                  into: &output)
        guard let module = try ELFModule(output.span) else {
          throw .process
        }
        return try module.architecture
      })
    }
  }
#else
  private static var machine: String {
#if arch(arm64)
    "arm64"
#elseif arch(arm)
    "arm"
#elseif arch(x86_64)
    "x86_64"
#elseif arch(i386)
    "i386"
#elseif arch(riscv64)
    "riscv64"
#else
    "unknown"
#endif
  }
#endif
}

#endif
