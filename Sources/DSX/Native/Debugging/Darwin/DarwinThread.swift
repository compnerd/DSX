// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinThread: ~Copyable {
  internal let handle: thread_act_t

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    var list = try DarwinThreadList(identifier.process)
    handle = try list.take(identifier.thread)
  }

  deinit {
    _ = mach_port_deallocate(mach_task_self_, handle)
  }

  internal borrowing func synchronize() throws(Debuggee.Error) {
    let status = thread_abort_safely(handle)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .thread)
    }
  }
}

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
  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      let list = try DarwinThreadList(process)
      for index in 0 ..< list.count {
        let thread = list[index]
        let info = try metadata(thread)
        guard info.thread_id == self.thread.rawValue else {
          continue
        }
        let name = try name(thread)
        let queue = info.dispatch_qaddr == 0 ? nil : info.dispatch_qaddr
        return Debuggee.Thread.Info(thread: self, name: name, queue: queue)
      }
      throw .thread
    }
  }

  internal func context(_ layout: Debuggee.Thread.Layout) throws(Debuggee.Error)
      -> Debuggee.Thread.Context {
    let list = try DarwinThreadList(process)
    for index in 0 ..< list.count {
      let thread = list[index]
      let info = try metadata(thread)
      guard info.thread_id == layout.thread.rawValue else {
        continue
      }
      let pthread = try pointer(process, address: info.thread_handle)
      let storage: UInt64? =
          if let pthread, let size = layout.size, size == 4 || size == 8 {
            switch (layout.base, layout.address) {
            case (.some(let base), _) where base > 0:
              try offset(pthread, by: base)
            case (_, .some(let address)):
              try pointer(process, address: offset(pthread, by: address),
                          size: size)
            default:
              nil
            }
          } else {
            nil
          }
      let queue = try pointer(process, address: info.dispatch_qaddr)
      let quality: Debuggee.Thread.Quality? =
          if let storage, let index = layout.quality, let size = layout.size {
            try quality(process, storage: storage, index: index, size: size)
          } else {
            nil
          }
      return Debuggee.Thread.Context(pthread: pthread, storage: storage,
                                     queue: queue, quality: quality)
    }
    throw .thread
  }
}

@inline(__always)
internal func identity(_ thread: thread_t) throws(Debuggee.Error)
    -> ThreadIdentifier {
  try ThreadIdentifier(rawValue: metadata(thread).thread_id)
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
    throw Debuggee.Error(mach: status, invalid: .thread)
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
    throw Debuggee.Error(mach: status, invalid: .thread)
  }
  let name = decode(&info.pth_name)
  return name.isEmpty ? nil : name
}

private func offset(_ address: UInt64, by displacement: UInt64)
    throws(Debuggee.Error) -> UInt64 {
  let (value, overflow) = address.addingReportingOverflow(displacement)
  guard overflow == false else {
    throw .memory
  }
  return value
}

private func pointer(_ process: ProcessIdentifier, address: UInt64,
                     size: UInt64 = UInt64(MemoryLayout<UInt>.size))
    throws(Debuggee.Error) -> UInt64? {
  guard let value = try word(process, address: address, size: size),
      value > 0 else {
    return nil
  }
  return value
}

private func word(_ process: ProcessIdentifier, address: UInt64, size: UInt64)
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
  return value
}

private typealias QualityDecoder = @convention(c)
    (UInt, UnsafeMutablePointer<CInt>?, UnsafeMutablePointer<CInt>?) -> UInt32

private func quality(_ process: ProcessIdentifier, storage: UInt64,
                     index: UInt64, size: UInt64) throws(Debuggee.Error)
    -> Debuggee.Thread.Quality? {
  guard index > 0, index < UInt64.max,
      let symbol = dlsym(RTLD_DEFAULT, "_pthread_qos_class_decode") else {
    return nil
  }
  let (offset, overflow) = index.multipliedReportingOverflow(by: size)
  guard overflow == false else {
    return nil
  }
  let (address, invalid) = storage.addingReportingOverflow(offset)
  guard invalid == false,
      let priority = try word(process, address: address, size: size) else {
    return nil
  }
  let decode = unsafeBitCast(symbol, to: QualityDecoder.self)
  let value = decode(UInt(priority), nil, nil)
  return switch value {
  case QOS_CLASS_USER_INTERACTIVE.rawValue:
    Debuggee.Thread.Quality(value: value,
                            constant: "QOS_CLASS_USER_INTERACTIVE",
                            name: "User Interactive")
  case QOS_CLASS_USER_INITIATED.rawValue:
    Debuggee.Thread.Quality(value: value, constant: "QOS_CLASS_USER_INITIATED",
                            name: "User Initiated")
  case QOS_CLASS_DEFAULT.rawValue:
    Debuggee.Thread.Quality(value: value, constant: "QOS_CLASS_DEFAULT",
                            name: "Default")
  case QOS_CLASS_UTILITY.rawValue:
    Debuggee.Thread.Quality(value: value, constant: "QOS_CLASS_UTILITY",
                            name: "Utility")
  case QOS_CLASS_BACKGROUND.rawValue:
    Debuggee.Thread.Quality(value: value, constant: "QOS_CLASS_BACKGROUND",
                            name: "Background")
  case QOS_CLASS_UNSPECIFIED.rawValue:
    Debuggee.Thread.Quality(value: value, constant: "QOS_CLASS_UNSPECIFIED",
                            name: "Unspecified")
  default:
    nil
  }
}

#endif
