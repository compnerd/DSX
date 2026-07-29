// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension Debuggee.Error {
  internal var message: String {
    if case .premature(let status) = self {
      let code = UInt32(bitPattern: status)
      return "Process prematurely exited with 0x\(String(code, radix: 16))"
    }
    let code: CInt? = switch self {
    case .launch(let value), .system(let value): value
    default: nil
    }
    guard let code else {
      return description
    }
    var buffer = InlineArray<512, WCHAR> { _ in 0 }
    let message: String? = withUnsafeMutablePointer(to: &buffer) { buffer in
      buffer.withMemoryRebound(to: WCHAR.self, capacity: 512) { buffer in
        let flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS
        let count = FormatMessageW(flags, nil, DWORD(bitPattern: code), 0,
                                   buffer, 512, nil)
        guard count > 0 else {
          return nil
        }
        return String(decodingCString: buffer, as: UTF16.self)
      }
    }
    guard var message else {
      return description
    }
    while let last = message.last, last == "\r" || last == "\n" {
      message.removeLast()
    }
    return message
  }
}
#endif
