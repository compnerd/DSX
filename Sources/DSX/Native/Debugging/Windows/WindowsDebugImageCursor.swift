// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal struct WindowsDebugImageCursor {
  private var iterator: Dictionary<UInt64, String>.Iterator

  internal init(_ images: consuming Dictionary<UInt64, String>) {
    iterator = images.makeIterator()
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Image? {
    while let (address, path) = iterator.next() {
      guard !path.isEmpty else {
        continue
      }
      return Debuggee.Image(path: path,
                            base: Debuggee.Address(rawValue: address))
    }
    return nil
  }
}

extension WindowsDebugControl {
  internal func images(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> WindowsDebugImageCursor {
    guard self.process == process else {
      throw .process
    }
    // A DLL's debug event precedes its insertion into the loader's lists.
    // Toolhelp can therefore omit the image while its load event is pending.
    return WindowsDebugImageCursor(images)
  }
}
#endif
