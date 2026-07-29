// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
extension HostProcessRecord {
  internal func reap() throws(Debuggee.Error) -> Bool {
    try NativeProcess.reap(information.process)
  }

  internal func terminate() throws(Debuggee.Error) {
    try NativeProcess.terminate(information.process)
  }
}
#endif
