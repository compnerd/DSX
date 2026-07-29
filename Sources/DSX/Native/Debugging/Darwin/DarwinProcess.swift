// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

extension ProcessIdentifier {
  internal static func snapshot() throws(Debuggee.Error)
      -> Array<ProcessIdentifier> {
    let required = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard required >= 0 else {
      throw UnixError.debuggee(errno, invalid: .process)
    }
    let stride = MemoryLayout<pid_t>.stride
    var identifiers =
        Array<pid_t>(repeating: 0, count: Int(required) / stride + 32)
    let capacity = identifiers.count * stride
    let written =
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, &identifiers, Int32(capacity))
    guard written >= 0 else {
      throw UnixError.debuggee(errno, invalid: .process)
    }
    let count = Int(written) / stride
    var processes = Array<ProcessIdentifier>()
    processes.reserveCapacity(count)
    for identifier in identifiers.prefix(count) where identifier > 0 {
      processes.append(ProcessIdentifier(rawValue: UInt64(identifier)))
    }
    return processes
  }

  internal var info: Debuggee.Process.Info {
    get throws(Debuggee.Error) {
      let identifier = try native
      var status = proc_bsdinfo()
      let count =
          proc_pidinfo(identifier, PROC_PIDTBSDINFO, 0, &status,
                       Int32(MemoryLayout<proc_bsdinfo>.size))
      guard count == MemoryLayout<proc_bsdinfo>.size else {
        throw UnixError.debuggee(errno, invalid: .process)
      }
      if status.pbi_status == SZOMB {
        throw .process
      }
      var architecture = proc_archinfo()
      let arch =
          proc_pidinfo(identifier, 19, 0, &architecture,
                       Int32(MemoryLayout<proc_archinfo>.size))
      guard arch == MemoryLayout<proc_archinfo>.size else {
        throw UnixError.debuggee(errno, invalid: .process)
      }
      let parent: ProcessIdentifier? = if status.pbi_ppid > 0 {
        ProcessIdentifier(rawValue: UInt64(status.pbi_ppid))
      } else {
        nil
      }
      let command = decode(&status.pbi_comm)
      let system = try? platform
      let path = ProcessIdentifier.path(identifier, fallback: command)
      let arguments = try ProcessIdentifier.arguments(identifier)
      let machine = ProcessIdentifier.machine(architecture.p_cputype)
      let header = try? self.header
      return Debuggee.Process.Info(process: self, parent: parent, name: path,
                                   arguments: arguments, architecture: machine,
                                   system: system,
                                   cpu: header.map { UInt64($0.cpu) },
                                   subtype: header.map { UInt64($0.subtype) })
    }
  }

  private static func path(_ process: pid_t, fallback: String) -> String {
    var path = Array<CChar>(repeating: 0, count: Int(PATH_MAX))
    let count = path.withUnsafeMutableBytes { buffer in
      proc_pidpath(process, buffer.baseAddress, UInt32(buffer.count))
    }
    guard count > 0 else {
      return fallback
    }
    return path.withUnsafeBufferPointer { path in
      guard let base = path.baseAddress else {
        return fallback
      }
      return String(cString: base)
    }
  }

  private static func arguments(_ process: pid_t) throws(Debuggee.Error)
      -> Array<String> {
    var query = [CTL_KERN, KERN_PROCARGS2, process]
    var required = 0
    guard sysctl(&query, u_int(query.count), nil, &required, nil, 0) == 0 else {
      if errno == EACCES || errno == EPERM {
        return []
      }
      throw UnixError.debuggee(errno, invalid: .process)
    }
    var bytes = Array<UInt8>(repeating: 0, count: required + 128)
    var count = bytes.count
    let status = bytes.withUnsafeMutableBytes { buffer in
      sysctl(&query, u_int(query.count), buffer.baseAddress, &count, nil, 0)
    }
    guard status == 0 else {
      if errno == EACCES || errno == EPERM {
        return []
      }
      throw UnixError.debuggee(errno, invalid: .process)
    }
    guard count >= MemoryLayout<CInt>.size else {
      throw .process
    }
    var total: CInt = 0
    withUnsafeMutableBytes(of: &total) { destination in
      destination.copyBytes(from: bytes.prefix(destination.count))
    }
    guard total >= 0 else {
      throw .process
    }
    var offset = MemoryLayout<CInt>.size
    guard skip(&offset, in: bytes, count: count) else {
      throw .process
    }
    while offset < count, bytes[offset] == 0 {
      offset += 1
    }
    var arguments = Array<String>()
    arguments.reserveCapacity(Int(total))
    for _ in 0 ..< total {
      let start = offset
      guard skip(&offset, in: bytes, count: count) else {
        throw .process
      }
      arguments.append(String(decoding: bytes[start ..< offset - 1],
                              as: UTF8.self))
    }
    return arguments
  }

  private static func skip(_ offset: inout Int,
                           in bytes: borrowing Array<UInt8>,
                           count: Int) -> Bool {
    while offset < count {
      offset += 1
      if bytes[offset - 1] == 0 {
        return true
      }
    }
    return false
  }

  private static func machine(_ type: cpu_type_t) -> String {
    switch type {
    case CPU_TYPE_ARM:
      "arm"
    case CPU_TYPE_ARM64:
      "arm64"
    case CPU_TYPE_X86:
      "i386"
    case CPU_TYPE_X86_64:
      "x86_64"
    default:
      "unknown"
    }
  }

}

#endif
