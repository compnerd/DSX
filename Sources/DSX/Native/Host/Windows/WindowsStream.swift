// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT
internal import WinSDK

internal enum WindowsStreamHandle {
  case descriptor(CInt)
  case native(HANDLE)
  case standard(HANDLE)
}

internal enum WindowsStream {
  internal typealias Handle = WindowsStreamHandle

  internal static func close(_ handle: WindowsStreamHandle) {
    if case .native(let handle) = handle {
      _ = CloseHandle(handle)
    }
  }

  internal static func open(_ endpoint: StreamEndpoint) throws(TransportError)
      -> WindowsStreamHandle {
    switch endpoint {
    case .descriptor(let handle): try descriptor(handle)
    case .device(let path): try native(path)
    case .notification(let path):
      try native(pipe(path), access: GENERIC_WRITE)
    case .pipe(let path): try native(pipe(path))
    }
  }

  internal static func wait(_ handle: WindowsStreamHandle, timeout: Int32,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    let native = try resolve(handle)
    let interval = Int32(Configuration.Process.Interval)
    let timeout = if events.isEmpty {
      timeout
    } else {
      timeout < 0 ? interval : min(timeout, interval)
    }
    let duration = timeout < 0 ? INFINITE : DWORD(timeout)
    if GetFileType(native) == FILE_TYPE_PIPE {
      let deadline =
          Deadline(milliseconds: UInt64(duration), now: GetTickCount64())
      while true {
        var available: DWORD = 0
        guard PeekNamedPipe(native, nil, 0, nil, &available, nil) else {
          let code = GetLastError()
          if code == ERROR_BROKEN_PIPE {
            return .channel
          }
          throw .read(CInt(bitPattern: code))
        }
        if available > 0 {
          return .channel
        }
        let remaining = timeout < 0 ? UInt64(interval)
                                    : deadline.remaining(GetTickCount64())
        if remaining == 0 {
          return .timeout
        }
        Sleep(DWORD(min(remaining, UInt64(interval))))
      }
    }
    let status = WaitForSingleObject(native, duration)
    return switch status {
    case WAIT_OBJECT_0: .channel
    case WAIT_TIMEOUT: .timeout
    default: throw .read(CInt(GetLastError()))
    }
  }

  internal static func receive(_ handle: WindowsStreamHandle,
                               _ buffer: UnsafeMutableRawPointer,
                               _ count: Int) throws(TransportError) -> Int {
    switch handle {
    case .descriptor(let descriptor):
      let result = _read(descriptor, buffer, UInt32(clamping: count))
      guard result >= 0 else {
        throw .read(errno)
      }
      return Int(result)
    case .native(let handle), .standard(let handle):
      var result: DWORD = 0
      let status =
          ReadFile(handle, buffer, DWORD(clamping: count), &result, nil)
      guard status else {
        let code = GetLastError()
        if code == ERROR_BROKEN_PIPE {
          return 0
        }
        throw .read(CInt(bitPattern: code))
      }
      return Int(result)
    }
  }

  internal static func transmit(_ handle: WindowsStreamHandle,
                                _ buffer: UnsafeRawPointer,
                                _ count: Int) throws(TransportError) -> Int {
    switch handle {
    case .descriptor(let descriptor):
      let result = _write(descriptor, buffer, UInt32(clamping: count))
      guard result >= 0 else {
        throw .write(errno)
      }
      return Int(result)
    case .native(let handle), .standard(let handle):
      var result: DWORD = 0
      let status =
          WriteFile(handle, buffer, DWORD(clamping: count), &result, nil)
      guard status else {
        throw .write(CInt(GetLastError()))
      }
      return Int(result)
    }
  }

  private static func native(_ path: String,
                             access: DWORD = GENERIC_READ | GENERIC_WRITE)
      throws(TransportError) -> WindowsStreamHandle {
    let handle = withUTF16CString(path) {
      CreateFileW($0, access, FILE_SHARE_READ | FILE_SHARE_WRITE, nil,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let handle else {
      throw .open(CInt(GetLastError()))
    }
    if handle == INVALID_HANDLE_VALUE {
      throw .open(CInt(GetLastError()))
    }
    return .native(handle)
  }

  private static func descriptor(_ descriptor: CInt) throws(TransportError)
      -> WindowsStreamHandle {
    if let standard = standard(descriptor) {
      return .standard(standard)
    }
    _ = try WindowsStream.handle(for: descriptor)
    return .descriptor(descriptor)
  }

  private static func resolve(_ handle: WindowsStreamHandle)
      throws(TransportError) -> HANDLE? {
    switch handle {
    case .descriptor(let descriptor):
      try WindowsStream.handle(for: descriptor)
    case .native(let handle), .standard(let handle):
      handle
    }
  }

  private static func standard(_ descriptor: CInt) -> HANDLE? {
    let identifier: DWORD? = switch descriptor {
    case STDIN_FILENO: STD_INPUT_HANDLE
    case STDOUT_FILENO: STD_OUTPUT_HANDLE
    case STDERR_FILENO: STD_ERROR_HANDLE
    default: nil
    }
    guard let identifier else {
      return nil
    }
    let handle = GetStdHandle(identifier)
    guard let handle else {
      return nil
    }
    if handle == INVALID_HANDLE_VALUE {
      return nil
    }
    return handle
  }

  private static func handle(for descriptor: CInt) throws(TransportError)
      -> HANDLE? {
    let previous =
        _set_thread_local_invalid_parameter_handler { _, _, _, _, _ in }
    defer {
      _ = _set_thread_local_invalid_parameter_handler(previous)
    }
    let value = _get_osfhandle(descriptor)
    if value == -1 {
      throw .descriptor(errno)
    }
    return HANDLE(bitPattern: value)
  }

  private static func pipe(_ path: String) -> String {
    let prefix = #"\\.\pipe\"#
    return if path.hasPrefix(prefix) {
      path
    } else {
      prefix + path
    }
  }
}
#endif
