// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

private typealias _pthread_qos_class_decodeBinding =
    LazyBinding<@convention(c) (UInt, UnsafeMutablePointer<CInt>?,
                                UnsafeMutablePointer<UInt>?) -> UInt32>

extension _pthread_qos_class_decodeBinding {
  fileprivate func callAsFunction(_ priority: UInt,
                                  _ relative: UnsafeMutablePointer<CInt>?,
                                  _ flags: UnsafeMutablePointer<UInt>?)
      -> UInt32 {
    function(priority, relative, flags)
  }
}

private let _pthread_qos_class_decode =
    _pthread_qos_class_decodeBinding(module: RTLD_DEFAULT,
                                     "_pthread_qos_class_decode")

extension ProcessThreadIdentifier {
  internal func context(_ layout: Debuggee.Thread.Layout,
                        control: borrowing NativeDebugControl =
                            NativeDebugControl()) throws(Debuggee.Error)
      -> Debuggee.Thread.Context {
    let list = try DarwinThreadList(process, control: control)
    for index in 0 ..< list.count {
      let thread = list[index]
      let info = try thread_identifier_info(thread)
      guard info.thread_id == layout.thread.rawValue else {
        continue
      }
      guard info.thread_handle > 0 || info.dispatch_qaddr > 0 else {
        return Debuggee.Thread.Context(pthread: nil, storage: nil, queue: nil,
                                       quality: nil)
      }
      let task = try control.task(process)
      let pthread = task.pointer(at: info.thread_handle)
      let storage: UInt64? =
          if let pthread, let size = layout.size, size == 4 || size == 8 {
            switch (layout.base, layout.address) {
            case let (.some(base), _) where base > 0:
              try offset(pthread, by: base)
            case let (_, .some(address)):
              try task.pointer(at: offset(pthread, by: address), size: size)
            default:
              nil
            }
          } else {
            nil
          }
      let queue = task.pointer(at: info.dispatch_qaddr)
      let quality: Debuggee.Thread.Quality? =
          if let storage, let index = layout.quality, let size = layout.size {
            task.quality(storage: storage, index: index, size: size)
          } else {
            nil
          }
      return Debuggee.Thread.Context(pthread: pthread, storage: storage,
                                     queue: queue, quality: quality)
    }
    throw .thread
  }
}

private func offset(_ address: UInt64, by displacement: UInt64)
    throws(Debuggee.Error) -> UInt64 {
  let (value, overflow) = address.addingReportingOverflow(displacement)
  guard overflow == false else {
    throw .memory
  }
  return value
}

extension DarwinTask {
  fileprivate func pointer(at address: UInt64,
                           size: UInt64 = UInt64(MemoryLayout<UInt>.size))
      -> UInt64? {
    guard let value = word(at: address, size: size), value > 0 else {
      return nil
    }
    return value
  }

  private func word(at address: UInt64, size: UInt64) -> UInt64? {
    guard address > 0, size == 4 || size == 8 else {
      return nil
    }
    var value: UInt64 = 0
    var read: mach_vm_size_t = 0
    let status = withUnsafeMutablePointer(to: &value) { value in
      mach_vm_read_overwrite(handle, address, size,
                             mach_vm_address_t(UInt(bitPattern: value)), &read)
    }
    guard status == KERN_SUCCESS, read == size else {
      return nil
    }
    return value
  }

  fileprivate func quality(storage: UInt64, index: UInt64, size: UInt64)
      -> Debuggee.Thread.Quality? {
    guard index > 0, index < UInt64.max, let _pthread_qos_class_decode else {
      return nil
    }
    let (offset, overflow) = index.multipliedReportingOverflow(by: size)
    guard overflow == false else {
      return nil
    }
    let (address, invalid) = storage.addingReportingOverflow(offset)
    guard invalid == false, let priority = word(at: address, size: size) else {
      return nil
    }
    let value = _pthread_qos_class_decode(UInt(priority), nil, nil)
    return switch value {
    case QOS_CLASS_USER_INTERACTIVE.rawValue:
      Debuggee.Thread.Quality(value: value,
                              constant: "QOS_CLASS_USER_INTERACTIVE",
                              name: "User Interactive")
    case QOS_CLASS_USER_INITIATED.rawValue:
      Debuggee.Thread.Quality(value: value,
                              constant: "QOS_CLASS_USER_INITIATED",
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
}

#endif
