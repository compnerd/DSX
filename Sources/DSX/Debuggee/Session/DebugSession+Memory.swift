// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct MemoryAllocation: Sendable {
  internal let process: ProcessIdentifier
  internal let address: Debuggee.Address
  internal let size: UInt64
}

extension DebugSession {
  @inline(never)
  internal func read(_ process: ProcessIdentifier, address: Debuggee.Address,
                     size: Int, mapping: Debuggee.MemoryRegion? = nil,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let start = output.count
    try NativeMemory.read(process, address: address, size: size,
                          mapping: mapping, into: &output)
    breakpoints.restore(process, address: address, start: start,
                        output: &output)
  }

  internal mutating func write(_ process: ProcessIdentifier,
                               address: Debuggee.Address,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    try breakpoints.write(process, address: address, bytes: bytes)
  }

  internal mutating func allocate(_ process: ProcessIdentifier, size: UInt64,
                                  readable: Bool, writable: Bool,
                                  executable: Bool) throws(Debuggee.Error)
      -> Debuggee.Address {
    let address = try NativeMemory.allocate(process, size: size,
                                            readable: readable,
                                            writable: writable,
                                            executable: executable,
                                            control: &control)
    allocations.append(MemoryAllocation(process: process, address: address,
                                        size: size))
    return address
  }

  internal mutating func deallocate(_ process: ProcessIdentifier,
                                    address: Debuggee.Address)
      throws(Debuggee.Error) {
    guard let index = allocations.firstIndex(where: { allocation in
      allocation.process == process && allocation.address == address
    }) else {
      throw .memory
    }
    let allocation = allocations[index]
    try NativeMemory.deallocate(process, address: address,
                                size: allocation.size, control: &control)
    allocations.remove(at: index)
  }

  internal mutating func deallocate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    while let allocation = allocations.last(where: { allocation in
        allocation.process == process
    }) {
      try deallocate(process, address: allocation.address)
    }
  }

  internal mutating func complete(_ event: borrowing Debuggee.Event) {
    let process: ProcessIdentifier
    switch event {
    case .executed(let thread):
      process = thread.process
    case .exited(let identifier, _):
      process = identifier
    case .terminated(let thread, _):
      return snapshots.removeAll { snapshot in
        snapshot.thread == thread
      }
    case .forked, .image, .output, .started, .stopped:
      return
    }
    allocations.removeAll { allocation in
      allocation.process == process
    }
    snapshots.removeAll { snapshot in
      snapshot.thread.process == process
    }
    breakpoints.forget(process)
  }
}
