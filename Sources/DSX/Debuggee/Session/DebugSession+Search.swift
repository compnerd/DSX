// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal func search(_ process: ProcessIdentifier, address: Debuggee.Address,
                       length: UInt64, pattern: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Debuggee.Address? {
    let chunk = if length < UInt64(Configuration.FileTransferCapacity) {
      Int(length)
    } else {
      Configuration.FileTransferCapacity
    }
    let capacity = chunk + pattern.count - 1
    return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                             { buffer throws(Debuggee.Error) in
      var consumed: UInt64 = 0
      var retained = 0
      while consumed < length {
        let remaining = length - consumed
        let (raw, overflow) = address.rawValue.addingReportingOverflow(consumed)
        if overflow {
          throw .memory
        }
        let next = Debuggee.Address(rawValue: raw)
        let region = try NativeMemory.region(process, address: next)
        if region.address.rawValue > raw {
          let gap = min(region.address.rawValue - raw, remaining)
          consumed += gap
          retained = 0
          continue
        }
        let offset = raw - region.address.rawValue
        guard offset < region.size else {
          throw .memory
        }
        let available = min(region.size - offset, remaining)
        guard available > 0 else {
          throw .memory
        }
        if region.readable {
          let requested = Int(min(UInt64(chunk), available))
          var output = OutputSpan(buffer: buffer, initializedCount: retained)
          try read(process, address: next, size: requested, mapping: region,
                   into: &output)
          let received = output.count - retained
          guard received > 0 else {
            throw .memory
          }
          let start = consumed - UInt64(retained)
          if let offset = match(output.span, pattern: pattern) {
            let displacement = start + UInt64(offset)
            let (raw, overflow) =
                address.rawValue.addingReportingOverflow(displacement)
            if overflow {
              throw .memory
            }
            return Debuggee.Address(rawValue: raw)
          }
          consumed += UInt64(received)
          retained = min(pattern.count - 1, output.count)
          let suffix = output.count - retained
          for index in 0 ..< retained {
            buffer[index] = output[suffix + index]
          }
        } else {
          consumed += available
          retained = 0
        }
      }
      return nil
    })
  }
}

private func match(_ bytes: borrowing Span<UInt8>,
                   pattern: borrowing Span<UInt8>) -> Int? {
  guard pattern.count <= bytes.count else {
    return nil
  }
  for offset in 0 ... bytes.count - pattern.count {
    var matched = true
    for index in 0 ..< pattern.count {
      if bytes[offset + index] != pattern[index] {
        matched = false
        break
      }
    }
    if matched {
      return offset
    }
  }
  return nil
}
