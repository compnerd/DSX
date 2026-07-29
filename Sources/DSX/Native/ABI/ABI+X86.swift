// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(i386) || arch(x86_64)
extension ABI {
  internal static var watchpoint: StaticString {
    "after"
  }

  internal static func role(_ register: RegisterRecord) -> RegisterRole? {
#if arch(x86_64)
#if os(Windows)
    switch register.identifier.rawValue {
    case 2: .argument(1)
    case 3: .argument(2)
    case 8: .argument(3)
    case 9: .argument(4)
    default: register.role
    }
#else
    switch register.identifier.rawValue {
    case 5: .argument(1)
    case 4: .argument(2)
    case 3: .argument(3)
    case 2: .argument(4)
    case 8: .argument(5)
    case 9: .argument(6)
    default: register.role
    }
#endif
#else
    register.role
#endif
  }

#if arch(i386)
  internal static var machine: StaticString {
    "i386"
  }

  internal static var width: Int {
    32
  }
#else
  internal static var machine: StaticString {
    "x86_64"
  }

  internal static var width: Int {
    64
  }
#endif
}
#endif
