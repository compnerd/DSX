// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(FreeBSD) || os(OpenBSD)) && arch(x86_64)
/// Native register offsets for the x86-64 register profile.
internal struct BSDX86RegisterLayout {
  internal let offset: Int
  internal let native: Int
  internal let size: Int
}

extension BSDX86RegisterLayout {
  internal init(_ register: RegisterIdentifier) throws(Debuggee.Error) {
#if os(FreeBSD)
    self = switch register.rawValue {
    case 0: BSDX86RegisterLayout(offset: 112, native: 8, size: 8)
    case 1: BSDX86RegisterLayout(offset: 88, native: 8, size: 8)
    case 2: BSDX86RegisterLayout(offset: 104, native: 8, size: 8)
    case 3: BSDX86RegisterLayout(offset: 96, native: 8, size: 8)
    case 4: BSDX86RegisterLayout(offset: 72, native: 8, size: 8)
    case 5: BSDX86RegisterLayout(offset: 64, native: 8, size: 8)
    case 6: BSDX86RegisterLayout(offset: 80, native: 8, size: 8)
    case 7: BSDX86RegisterLayout(offset: 160, native: 8, size: 8)
    case 8: BSDX86RegisterLayout(offset: 56, native: 8, size: 8)
    case 9: BSDX86RegisterLayout(offset: 48, native: 8, size: 8)
    case 10: BSDX86RegisterLayout(offset: 40, native: 8, size: 8)
    case 11: BSDX86RegisterLayout(offset: 32, native: 8, size: 8)
    case 12: BSDX86RegisterLayout(offset: 24, native: 8, size: 8)
    case 13: BSDX86RegisterLayout(offset: 16, native: 8, size: 8)
    case 14: BSDX86RegisterLayout(offset: 8, native: 8, size: 8)
    case 15: BSDX86RegisterLayout(offset: 0, native: 8, size: 8)
    case 16: BSDX86RegisterLayout(offset: 136, native: 8, size: 8)
    case 17: BSDX86RegisterLayout(offset: 152, native: 4, size: 4)
    case 18: BSDX86RegisterLayout(offset: 144, native: 4, size: 4)
    case 19: BSDX86RegisterLayout(offset: 168, native: 4, size: 4)
    case 20: BSDX86RegisterLayout(offset: 134, native: 2, size: 4)
    case 21: BSDX86RegisterLayout(offset: 132, native: 2, size: 4)
    case 22: BSDX86RegisterLayout(offset: 124, native: 2, size: 4)
    case 23: BSDX86RegisterLayout(offset: 126, native: 2, size: 4)
    default: throw .register
    }
#else
    let offset: Int = switch register.rawValue {
    case 0: 112
    case 1: 104
    case 2: 24
    case 3: 16
    case 4: 8
    case 5: 0
    case 6: 96
    case 7: 120
    case 8: 32
    case 9: 40
    case 10: 48
    case 11: 56
    case 12: 64
    case 13: 72
    case 14: 80
    case 15: 88
    case 16: 128
    case 17: 136
    case 18: 144
    case 19: 152
    case 20: 160
    case 21: 168
    case 22: 176
    case 23: 184
    default: throw .register
    }
    let size = register.rawValue < 17 ? 8 : 4
    self.init(offset: offset, native: size, size: size)
#endif
  }
}
#endif
