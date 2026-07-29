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
    ]
#endif
    var length = 0
    guard sysctl(&query, u_int(query.count), nil, &length, nil, 0) == 0 else {
      throw UnixError.debuggee(errno, invalid: .process)
    }
    let stride = MemoryLayout<kinfo_proc>.stride
    var records =
        Array<kinfo_proc>(repeating: kinfo_proc(), count: length / stride)
    let status = records.withUnsafeMutableBytes { records in
      sysctl(&query, u_int(query.count), records.baseAddress, &length, nil, 0)
    }
    guard status == 0 else {
      throw UnixError.debuggee(errno, invalid: .process)
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
      let records = try records
      guard var record = records.first else {
        throw .process
      }
#if os(FreeBSD)
      let pid = record.ki_ppid
      let name = decode(&record.ki_comm)
#else
      let pid = record.p_ppid
      let name = decode(&record.p_comm)
#endif
      let parent: ProcessIdentifier? = if pid > 0 {
        ProcessIdentifier(rawValue: UInt64(pid))
      } else {
        nil
      }
      return Debuggee.Process.Info(process: self, parent: parent, name: name,
                                   architecture: ProcessIdentifier.machine)
    }
  }

  private var records: Array<kinfo_proc> {
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
      ]
#endif
      var record = kinfo_proc()
      var length = MemoryLayout<kinfo_proc>.stride
      let status = withUnsafeMutablePointer(to: &record) { record in
        sysctl(&query, u_int(query.count), record, &length, nil, 0)
      }
      guard status == 0 else {
        throw UnixError.debuggee(errno, invalid: .process)
      }
      guard length >= MemoryLayout<kinfo_proc>.stride else {
        return Array<kinfo_proc>()
      }
      return [record]
    }
  }

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

}

#endif
