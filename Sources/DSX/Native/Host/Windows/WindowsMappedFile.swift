// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsMappedFile: ~Copyable {
  private let address: UnsafePointer<UInt8>
  private let count: Int

  internal init(_ path: String) throws(Debuggee.Error) {
    let raw = withUTF16CString(path) { path in
      CreateFileW(path, GENERIC_READ,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nil,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let handle = WindowsHandle(raw) else {
      throw WindowsError.debuggee(GetLastError())
    }
    var size = LARGE_INTEGER()
    guard GetFileSizeEx(handle.value, &size) else {
      throw WindowsError.debuggee(GetLastError())
    }
    guard size.QuadPart > 0, UInt64(size.QuadPart) <= UInt64(Int.max) else {
      throw .process
    }
    let map = CreateFileMappingW(handle.value, nil, PAGE_READONLY, 0, 0, nil)
    guard let mapping = WindowsHandle(map) else {
      throw WindowsError.debuggee(GetLastError())
    }
    let view = MapViewOfFile(mapping.value, FILE_MAP_READ, 0, 0, 0)
    guard let address = view else {
      throw WindowsError.debuggee(GetLastError())
    }
    self.address = UnsafeRawPointer(address).assumingMemoryBound(to: UInt8.self)
    count = Int(size.QuadPart)
  }

  deinit {
    _ = UnmapViewOfFile(address)
  }

  @_lifetime(borrow self)
  internal borrowing func span() -> Span<UInt8> {
    Span(_unsafeStart: address, count: count)
  }
}
#endif
