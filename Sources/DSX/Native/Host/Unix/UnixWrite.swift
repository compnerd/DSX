// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
@_transparent
internal func write(_ handle: CInt, _ bytes: UnsafeRawPointer?, _ count: Int,
                    suppressing signal: CInt) -> Int {
  WritePolicy.write(handle, bytes, count, suppressing: signal)
}
#endif
