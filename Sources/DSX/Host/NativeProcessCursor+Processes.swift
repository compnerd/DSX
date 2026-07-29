// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeProcessCursor {
  internal mutating func next() throws(Debuggee.Error)
      -> Debuggee.Process.Info? {
    while true {
      do {
        return try read()
      } catch .process, .access {
        continue
      } catch {
        throw error
      }
    }
  }
}
