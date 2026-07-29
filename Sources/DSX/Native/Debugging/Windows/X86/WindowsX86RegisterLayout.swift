// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

extension WindowsContext {
  internal static func step(_ context: inout CONTEXT) {
    context.EFlags |= kEFlagsTrap
  }
}

extension WindowsRegisters {
#if arch(i386)
  private static let kLayout: InlineArray<41, UInt32> = [
    0x040400b0, 0x040400ac, 0x040400a8, 0x040400a4, 0x040400c4,
    0x040400b4, 0x040400a0, 0x0404009c, 0x040400b8, 0x040400c0,
    0x040400bc, 0x040400c8, 0x04040098, 0x04040094, 0x04040090,
    0x0404008c, 0x0a0a00ec, 0x0a0a00fc, 0x0a0a010c, 0x0a0a011c,
    0x0a0a012c, 0x0a0a013c, 0x0a0a014c, 0x0a0a015c, 0x040200cc,
    0x040200ce, 0x040100d0, 0x040200d8, 0x040400d4, 0x040200e0,
    0x040400dc, 0x040200d2, 0x1010016c, 0x1010017c, 0x1010018c,
    0x1010019c, 0x101001ac, 0x101001bc, 0x101001cc, 0x101001dc,
    0x040400e4,
  ]
#else
  private static let kLayout: InlineArray<57, UInt32> = [
    0x08080078, 0x08080090, 0x08080080, 0x08080088, 0x080800a8,
    0x080800b0, 0x080800a0, 0x08080098, 0x080800b8, 0x080800c0,
    0x080800c8, 0x080800d0, 0x080800d8, 0x080800e0, 0x080800e8,
    0x080800f0, 0x080800f8, 0x04040044, 0x04020038, 0x04020042,
    0x0402003e, 0x0402003c, 0x0402003a, 0x04020040, 0x0a0a0120,
    0x0a0a0130, 0x0a0a0140, 0x0a0a0150, 0x0a0a0160, 0x0a0a0170,
    0x0a0a0180, 0x0a0a0190, 0x04020100, 0x04020102, 0x04010104,
    0x0402010c, 0x04040108, 0x04020114, 0x04040110, 0x04020106,
    0x101001a0, 0x101001b0, 0x101001c0, 0x101001d0, 0x101001e0,
    0x101001f0, 0x10100200, 0x10100210, 0x10100220, 0x10100230,
    0x10100240, 0x10100250, 0x10100260, 0x10100270, 0x10100280,
    0x10100290, 0x04040034,
  ]
#endif

  internal static func layout(_ register: RegisterIdentifier)
      throws(Debuggee.Error) -> (offset: Int, native: Int, size: Int) {
    guard register.rawValue < UInt32(WindowsRegisters.kLayout.count) else {
      throw .register
    }
    let layout = WindowsRegisters.kLayout[Int(register.rawValue)]
    let offset = Int(layout & 0x0000ffff)
    let native = Int(layout >> 16 & 0x000000ff)
    let size = Int(layout >> 24)
    return (offset, native, size)
  }
}
#endif
