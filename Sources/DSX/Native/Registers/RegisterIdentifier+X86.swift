// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(i386) || arch(x86_64)
extension RegisterIdentifier {
  /// Index of the independently addressable YMM upper half.
  internal var ymm: Int? {
#if arch(i386)
    let first = I386Register.ymm0h.rawValue
#else
    let first = X86_64Register.ymm0h.rawValue
#endif
    let index = rawValue &- first
    return index < RegisterConfiguration.vectors ? Int(index) : nil
  }
}
#endif
