// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

private let kPage = UInt64(getpagesize())

internal enum DarwinMemory {
  private typealias Failure = Debuggee.Error

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            mapping _: Debuggee.MemoryRegion? = nil,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let task = try DarwinTask(process)
    try output.withUnsafeMutableBufferPointer { data, offset throws(Failure) in
      let requested = min(size, data.count - offset)
      let page = kPage
      guard page > 0 else {
        throw .memory
      }
      var consumed = 0
      while consumed < requested {
        let (raw, overflow) =
            address.rawValue.addingReportingOverflow(UInt64(consumed))
        if overflow {
          throw .memory
        }
        let available = Int(page - raw % page)
        let length = min(requested - consumed, available)
        let base = data.baseAddress!.advanced(by: offset)
        let destination = mach_vm_address_t(UInt(bitPattern: base))
        var count: mach_vm_size_t = 0
        let status = mach_vm_read_overwrite(task.handle, raw,
                                            mach_vm_size_t(length), destination,
                                            &count)
        guard status == KERN_SUCCESS else {
          if consumed > 0 {
            return
          }
          throw Debuggee.Error(virtual: status)
        }
        guard count > 0 else {
          if consumed > 0 {
            return
          }
          throw .memory
        }
        let received = Int(count)
        offset += received
        consumed += received
        if received < length {
          return
        }
      }
    }
  }

  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    count = 0
    guard bytes.count > 0 else {
      return
    }
    let task = try DarwinTask(process)
    try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      while count < bytes.count {
        let (raw, overflow) =
            address.rawValue.addingReportingOverflow(UInt64(count))
        if overflow {
          throw .memory
        }
        var depth: natural_t = 0
        guard let mapping =
            try task.mapping(at: raw, depth: &depth) else {
          throw .memory
        }
        guard mapping.address <= raw else {
          throw .memory
        }
        let offset = raw - mapping.address
        guard offset < mapping.size else {
          throw .memory
        }

        let available = Int(clamping: mapping.size - offset)
        let requested =
            min(bytes.count - count, available, Int(mach_msg_type_number_t.max))
        let source = vm_offset_t(UInt(bitPattern: bytes.baseAddress! + count))
        let status = mach_vm_protect(task.handle, raw,
                                     mach_vm_size_t(requested), 0,
                                     VM_PROT_READ | VM_PROT_WRITE
                                         | VM_PROT_COPY)
        guard status == KERN_SUCCESS else {
          throw Debuggee.Error(virtual: status)
        }

        let written = mach_vm_write(task.handle, raw, source,
                                    mach_msg_type_number_t(requested))
        if written == KERN_SUCCESS {
          count += requested
        }
#if arch(arm64)
        var value = MATTR_VAL_CACHE_FLUSH
        let flushed = if written == KERN_SUCCESS {
          mach_vm_machine_attribute(task.handle, raw, mach_vm_size_t(requested),
                                    vm_machine_attribute_t(MATTR_CACHE), &value)
        } else {
          written
        }
#endif
        let restored = mach_vm_protect(task.handle, raw,
                                       mach_vm_size_t(requested), 0,
                                       mapping.protection)
        guard written == KERN_SUCCESS else {
          throw Debuggee.Error(virtual: written)
        }
#if arch(arm64)
        guard flushed == KERN_SUCCESS else {
          throw Debuggee.Error(virtual: flushed)
        }
#endif
        guard restored == KERN_SUCCESS else {
          throw Debuggee.Error(virtual: restored)
        }
      }
    }
  }

  internal static func patch(_ process: ProcessIdentifier,
                             thread _: ProcessThreadIdentifier?,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    try write(process, address: address, bytes: bytes, count: &count)
  }

  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address) throws(Debuggee.Error)
      -> Debuggee.MemoryRegion {
    let task = try DarwinTask(process)
    let requested = address.rawValue
    var depth: natural_t = 0
    guard let mapping = try task.mapping(at: requested, depth: &depth) else {
      return Debuggee.MemoryRegion(address: address,
                                   size: UInt64.max - requested,
                                   readable: false, writable: false,
                                   executable: false, mapped: false)
    }
    if mapping.address > requested {
      return Debuggee.MemoryRegion(address: address,
                                   size: mapping.address - requested,
                                   readable: false, writable: false,
                                   executable: false, mapped: false)
    }
    let protection = mapping.protection
    let address = Debuggee.Address(rawValue: mapping.address)
    return Debuggee.MemoryRegion(address: address, size: mapping.size,
                                 readable: protection & VM_PROT_READ != 0,
                                 writable: protection & VM_PROT_WRITE != 0,
                                 executable: protection & VM_PROT_EXECUTE != 0,
                                 kind: mapping.kind)
  }

  internal static func allocate(_ process: ProcessIdentifier, size: UInt64,
                                readable: Bool, writable: Bool,
                                executable: Bool,
                                control _: inout DarwinDebugControl)
      throws(Debuggee.Error) -> Debuggee.Address {
    let task = try DarwinTask(process)
    var address: mach_vm_address_t = 0
    var status = mach_vm_allocate(task.handle, &address, mach_vm_size_t(size),
                                  VM_FLAGS_ANYWHERE)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(virtual: status)
    }
    let protection = (readable ? VM_PROT_READ : 0)
                   | (writable ? VM_PROT_WRITE : 0)
                   | (executable ? VM_PROT_EXECUTE : 0)
    status = mach_vm_protect(task.handle, address, mach_vm_size_t(size), 0,
                             vm_prot_t(protection))
    guard status == KERN_SUCCESS else {
      _ = mach_vm_deallocate(task.handle, address, mach_vm_size_t(size))
      throw Debuggee.Error(virtual: status)
    }
    return Debuggee.Address(rawValue: address)
  }

  internal static func deallocate(_ process: ProcessIdentifier,
                                  address: Debuggee.Address, size: UInt64,
                                  control _: inout DarwinDebugControl)
      throws(Debuggee.Error) {
    let task = try DarwinTask(process)
    let status =
        mach_vm_deallocate(task.handle, address.rawValue, mach_vm_size_t(size))
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(virtual: status)
    }
  }
}

#endif
