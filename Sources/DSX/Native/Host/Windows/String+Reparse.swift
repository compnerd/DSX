// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import DSXShims
internal import WinSDK

extension String {
  internal init(reparse bytes: UnsafeRawBufferPointer) throws(Debuggee.Error) {
    let header = MemoryLayout<dsx_reparse_names>.size
    guard bytes.count >= header else {
      throw Debuggee.Error(windows: ERROR_INVALID_REPARSE_DATA)
    }
    let names = bytes.loadUnaligned(as: dsx_reparse_names.self)
    let start: Int = switch names.ReparseTag {
    case IO_REPARSE_TAG_SYMLINK: header + MemoryLayout<ULONG>.size
    case IO_REPARSE_TAG_MOUNT_POINT: header
    default: throw Debuggee.Error(windows: ERROR_NOT_A_REPARSE_POINT)
    }
    let fixed = MemoryLayout<ULONG>.size + 2 * MemoryLayout<USHORT>.size
    let extent = fixed + Int(names.ReparseDataLength)
    let offset = Int(names.SubstituteNameOffset)
    let length = Int(names.SubstituteNameLength)
    guard extent <= bytes.count, start <= extent, offset <= extent - start,
        length <= extent - start - offset, offset % 2 == 0,
        length % 2 == 0 else {
      throw Debuggee.Error(windows: ERROR_INVALID_REPARSE_DATA)
    }
    let begin = start + offset
    let buffer =
        UnsafeRawBufferPointer(rebasing: bytes[begin ..< begin + length])
    let value = buffer.bindMemory(to: WCHAR.self)
    let relative = names.ReparseTag == IO_REPARSE_TAG_SYMLINK &&
        bytes.loadUnaligned(fromByteOffset: header, as: ULONG.self) & 1 != 0
    // UTF-16 "\??\" identifies an NT DOS-device path. "\??\UNC\" needs two
    // leading separators after removing the device prefix.
    let separator: WCHAR = 0x005c
    let question: WCHAR = 0x003f
    var skipped = 0
    var prefix = ""
    if relative == false, value.count >= 4, value[0] == separator,
        value[1] == question, value[2] == question, value[3] == separator {
      skipped = 4
      let network = value.count >= 8 && value[4] == 0x0055 &&
          value[5] == 0x004e && value[6] == 0x0043 && value[7] == separator
      let drive = value.count >= 6 && value[5] == 0x003a
      switch (network, drive) {
      case (true, _):
        skipped = 8
        prefix = #"\\"#
      case (false, true):
        break
      case (false, false):
        // Volume GUIDs and other device paths retain Win32's extended prefix.
        prefix = #"\\?\"#
      }
    }
    let path = UnsafeBufferPointer(rebasing: value[skipped...])
    let result = String(decoding: path, as: UTF16.self)
    self = prefix.isEmpty ? result : prefix + result
  }
}
#endif
