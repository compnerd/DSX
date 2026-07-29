// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension ProcessIdentifier {
  internal func auxiliary(offset: UInt64, limit: Int,
                          into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    let identifier = try native
    return try LinuxProcFS.read("/proc/\(identifier)/auxv", offset: offset,
                                limit: limit, into: &output)
  }
}

extension ProcessThreadIdentifier {
  internal func signal(offset: UInt64, limit: Int,
                       into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    let identifier = try thread.native
    var information = siginfo_t()
    let status = withUnsafeMutablePointer(to: &information) { information in
      ptrace(PTRACE_GETSIGINFO, identifier, nil,
             UnsafeMutableRawPointer(information))
    }
    guard status == 0 else {
      throw LinuxProcFS.failure(errno)
    }
    return withUnsafeBytes(of: &information) { bytes in
      let start = min(offset, UInt64(bytes.count))
      let available = bytes.count - Int(start)
      let count = min(available, limit)
      for index in Int(start) ..< Int(start) + count {
        output.append(bytes[index])
      }
      return count < available ? .more : .last
    }
  }
}

#endif
