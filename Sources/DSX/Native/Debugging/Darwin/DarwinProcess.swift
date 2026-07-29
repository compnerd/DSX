// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

extension ProcessIdentifier {
  internal static func snapshot() throws(Debuggee.Error)
      -> Array<ProcessIdentifier> {
    let required = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard required >= 0 else {
      throw Debuggee.Error(unix: errno, invalid: .process)
    }
    let stride = MemoryLayout<pid_t>.stride
    var identifiers =
        Array<pid_t>(repeating: 0, count: Int(required) / stride + 32)
    let capacity = identifiers.count * stride
    let written =
        proc_listpids(UInt32(PROC_ALL_PIDS), 0, &identifiers, Int32(capacity))
    guard written >= 0 else {
      throw Debuggee.Error(unix: errno, invalid: .process)
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
        throw Debuggee.Error(unix: errno, invalid: .process)
      }
      if status.pbi_status == SZOMB {
        throw .process
      }
      var architecture = proc_archinfo()
      let arch =
          proc_pidinfo(identifier, PROC_PIDARCHINFO, 0, &architecture,
                       Int32(MemoryLayout<proc_archinfo>.size))
      guard arch == MemoryLayout<proc_archinfo>.size else {
        throw Debuggee.Error(unix: errno, invalid: .process)
      }
      let parent: ProcessIdentifier? = if status.pbi_ppid > 0 {
        ProcessIdentifier(rawValue: UInt64(status.pbi_ppid))
      } else {
        nil
      }
      let command = decode(&status.pbi_comm)
      let path = path(fallback: command)
      let arguments = try arguments()
      let machine = ProcessIdentifier.machine(architecture.p_cputype)
      // Enumeration must not request debug task ports for unrelated processes.
      let system = try? platform(path, architecture: machine)
      let cpu = UInt64(UInt32(bitPattern: architecture.p_cputype))
      let subtype = UInt64(UInt32(bitPattern: architecture.p_cpusubtype))
      return Debuggee.Process.Info(process: self, parent: parent, name: path,
                                   arguments: arguments, architecture: machine,
                                   system: system, cpu: cpu, subtype: subtype)
    }
  }

  private func platform(_ path: String, architecture: String)
      throws(Debuggee.Error) -> String? {
    let storage = try NativeMappedFile(path)
    return try MachOModule(storage.span(), requested: architecture)?.system
  }

  private func path(fallback: String) -> String {
    guard let process = try? native else {
      return fallback
    }
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

  private func arguments() throws(Debuggee.Error) -> Array<String> {
    let process = try native
    var query = [CTL_KERN, KERN_PROCARGS2, process]
    var required = 0
    guard sysctl(&query, u_int(query.count), nil, &required, nil, 0) == 0 else {
      if errno == EACCES || errno == EPERM {
        return []
      }
      throw Debuggee.Error(unix: errno, invalid: .process)
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
      throw Debuggee.Error(unix: errno, invalid: .process)
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
    let start = MemoryLayout<CInt>.size
    guard let end = bytes[start ..< count].firstIndex(of: 0) else {
      throw .process
    }
    var offset = end + 1
    while offset < count, bytes[offset] == 0 {
      offset += 1
    }
    var arguments = Array<String>()
    arguments.reserveCapacity(Int(total))
    for _ in 0 ..< total {
      let start = offset
      guard let end = bytes[start ..< count].firstIndex(of: 0) else {
        throw .process
      }
      arguments.append(String(decoding: bytes[start ..< end], as: UTF8.self))
      offset = end + 1
    }
    return arguments
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
