// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      let list = try DarwinThreadList(self)
      var threads = Array<ProcessThreadIdentifier>()
      threads.reserveCapacity(list.count)
      for index in 0 ..< list.count {
        let identifier = try identity(list[index])
        let pair = ProcessThreadIdentifier(process: self, thread: identifier)
        threads.append(pair)
      }
      return threads
    }
  }
}

extension ProcessThreadIdentifier {
  internal var alive: Bool {
    get throws(Debuggee.Error) {
      try process.threads.contains(self)
    }
  }

  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      let name = try name(self)
      return Debuggee.Thread.Info(thread: self, name: name)
    }
  }

  internal func context(_ layout: Debuggee.Thread.Layout) throws(Debuggee.Error)
      -> Debuggee.Thread.Context {
    let list = try DarwinThreadList(process)
    for index in 0 ..< list.count {
      let thread = list[index]
      guard try identity(thread) == layout.thread else {
        continue
      }
      let info = try metadata(thread)
      let pthread = try pointer(process, address: info.thread_handle)
      let storage: UInt64? = switch pthread {
      case _ where layout.base > 0:
        pthread.map { $0 + layout.base }
      case .some(let pthread):
        try pointer(process, address: pthread + layout.address,
                    size: layout.size)
      case .none:
        nil
      }
      let queue = try pointer(process, address: info.dispatch_qaddr)
      return Debuggee.Thread.Context(pthread: pthread, storage: storage,
                                     queue: queue)
    }
    throw .thread
  }
}

@inline(__always)
internal func identity(_ thread: thread_t) throws(Debuggee.Error)
    -> ThreadIdentifier {
  var info = thread_identifier_info()
  let bytes = MemoryLayout<thread_identifier_info>.size
  let size = bytes / MemoryLayout<integer_t>.size
  var length = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(length)) { info in
      thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), info,
                  &length)
    }
  }
  guard status == KERN_SUCCESS else {
    throw DarwinError.debuggee(status, invalid: .thread)
  }
  return ThreadIdentifier(rawValue: info.thread_id)
}

private func name(_ pair: ProcessThreadIdentifier) throws(Debuggee.Error)
    -> String? {
  let list = try DarwinThreadList(pair.process)
  for index in 0 ..< list.count {
    let thread = list[index]
    guard try identity(thread) == pair.thread else {
      continue
    }
    return try name(thread)
  }
  throw .thread
}

private func metadata(_ thread: thread_t) throws(Debuggee.Error)
    -> thread_identifier_info {
  var info = thread_identifier_info()
  let bytes = MemoryLayout<thread_identifier_info>.size
  let size = bytes / MemoryLayout<integer_t>.size
  var length = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(length)) { info in
      thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), info,
                  &length)
    }
  }
  guard status == KERN_SUCCESS else {
    throw DarwinError.debuggee(status, invalid: .thread)
  }
  return info
}

private func name(_ thread: thread_t) throws(Debuggee.Error) -> String? {
  var info = thread_extended_info()
  let bytes = MemoryLayout<thread_extended_info>.size
  let size = bytes / MemoryLayout<integer_t>.size
  var length = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(length)) { info in
      thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), info, &length)
    }
  }
  guard status == KERN_SUCCESS else {
    throw DarwinError.debuggee(status, invalid: .thread)
  }
  let name = decode(&info.pth_name)
  return name.isEmpty ? nil : name
}

private func pointer(_ process: ProcessIdentifier, address: UInt64,
                     size: UInt64 = UInt64(MemoryLayout<UInt>.size))
    throws(Debuggee.Error) -> UInt64? {
  guard address > 0, size == 4 || size == 8 else {
    return nil
  }
  let task = try DarwinTask(process)
  var value: UInt64 = 0
  var read: mach_vm_size_t = 0
  let status = withUnsafeMutablePointer(to: &value) { value in
    mach_vm_read_overwrite(task.handle, address, size,
                           mach_vm_address_t(UInt(bitPattern: value)), &read)
  }
  guard status == KERN_SUCCESS, read == size else {
    return nil
  }
  return value == 0 ? nil : value
}

#endif
