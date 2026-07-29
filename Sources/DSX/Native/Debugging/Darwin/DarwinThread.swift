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
        let identifier = try ThreadIdentifier(mach: list[index])
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
        let info = try thread_identifier_info(thread)
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
}

extension ThreadIdentifier {
  @inline(__always)
  internal init(mach thread: thread_t) throws(Debuggee.Error) {
    try self.init(rawValue: thread_identifier_info(thread).thread_id)
  }
}

extension thread_identifier_info {
  internal init(_ thread: thread_t) throws(Debuggee.Error) {
    var info = thread_identifier_info()
    let bytes = MemoryLayout<thread_identifier_info>.size
    let size = bytes / MemoryLayout<integer_t>.size
    var length = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &info) { info in
      let capacity = Int(length)
      return info.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0,
                    &length)
      }
    }
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .thread)
    }
    self = info
  }
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
  let name = withUnsafeBytes(of: &info.pth_name) {
    String(native: $0)
  }
  return name.isEmpty ? nil : name
}

#endif
