// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension Debuggee.Image {
  internal var offsets: Debuggee.ImageOffsets {
    get throws(Debuggee.Error) {
      let storage = try NativeMappedFile(path)
      guard let module = try PEModule(storage.span()) else {
        throw .process
      }
      let preferred = try module.base
      let offset = base.rawValue &- preferred
      return .sections(text: offset, data: offset)
    }
  }
}

extension ProcessIdentifier {
  internal var address: Debuggee.Address {
    get throws(Debuggee.Error) {
      Debuggee.Address(rawValue: 0)
    }
  }

  internal func images(_ style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    var cursor = try WindowsImageCursor(native)
    var images = Array<Debuggee.Image>()
    while let image = try cursor.next() {
      images.append(image)
    }
    return images
  }

  internal var linkage: Array<Debuggee.Image> {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal var image: Debuggee.Image? {
    get throws(Debuggee.Error) {
      var cursor = try WindowsImageCursor(native)
      return try cursor.next()
    }
  }

  internal var cache: Debuggee.SharedCache {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}

internal struct WindowsImageCursor: ~Copyable {
  private let handle: WindowsHandle
  private var record: MODULEENTRY32W
  private var started: Bool
  private var complete: Bool

  internal init(_ process: DWORD) throws(Debuggee.Error) {
    handle = try modules(process)
    record = MODULEENTRY32W()
    record.dwSize = DWORD(MemoryLayout<MODULEENTRY32W>.size)
    started = false
    complete = false
  }

  internal init(_ process: ProcessIdentifier, svr4: Bool)
      throws(Debuggee.Error) {
    if svr4 {
      throw .unsupported
    }
    try self.init(process.native)
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Image? {
    if complete {
      return nil
    }
    let main = started == false
    let result = if started {
      Module32NextW(handle.value, &record)
    } else {
      Module32FirstW(handle.value, &record)
    }
    started = true
    guard result else {
      let code = GetLastError()
      guard code == ERROR_NO_MORE_FILES else {
        throw WindowsError.debuggee(code, invalid: .process)
      }
      complete = true
      return nil
    }
    let base =
        Debuggee.Address(rawValue: UInt64(UInt(bitPattern: record.modBaseAddr)))
    let path = decode(&record.szExePath)
    return Debuggee.Image(path: path, base: base, main: main)
  }
}

private func modules(_ process: DWORD) throws(Debuggee.Error) -> WindowsHandle {
  while true {
    let flags = TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32
    let handle = CreateToolhelp32Snapshot(flags, process)
    if handle == INVALID_HANDLE_VALUE {
      let code = GetLastError()
      guard code == ERROR_BAD_LENGTH else {
        throw WindowsError.debuggee(code, invalid: .process)
      }
      continue
    }
    guard let handle else {
      throw WindowsError.debuggee(GetLastError(), invalid: .process)
    }
    return WindowsHandle(handle)
  }
}
#endif
