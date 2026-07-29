// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension Debuggee.Error {
  internal init(process code: DWORD) {
    self.init(windows: code, invalid: .process)
  }

  internal init(hresult: HRESULT) {
    let value = UInt32(bitPattern: CInt(hresult))
    if value & 0xffff0000 == 0x80070000 {
      self = Debuggee.Error(windows: DWORD(value & 0x0000ffff))
    } else {
      self = .system(CInt(hresult))
    }
  }

  internal init(memory code: DWORD) {
    self = switch code {
    case ERROR_INVALID_ADDRESS, ERROR_PARTIAL_COPY: .memory
    default: Debuggee.Error(windows: code, invalid: .process)
    }
  }

  internal init(windows code: DWORD) {
    self = switch code {
    case ERROR_ACCESS_DENIED: .access
    case ERROR_CALL_NOT_IMPLEMENTED, ERROR_NOT_SUPPORTED: .unsupported
    default: .system(CInt(bitPattern: code))
    }
  }

  internal init(windows code: DWORD, invalid: Debuggee.Error) {
    self = switch code {
    case ERROR_ACCESS_DENIED: .access
    case ERROR_INVALID_PARAMETER, ERROR_NOT_FOUND: invalid
    case ERROR_CALL_NOT_IMPLEMENTED, ERROR_NOT_SUPPORTED: .unsupported
    default: .system(CInt(bitPattern: code))
    }
  }

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
