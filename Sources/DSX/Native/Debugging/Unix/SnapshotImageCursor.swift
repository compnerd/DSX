// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Android) || os(Linux)
internal struct SnapshotImageCursor {
  private var images: IndexingIterator<Array<Debuggee.Image>>

  internal init(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    images = try process.images(.name).makeIterator()
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Image? {
    images.next()
  }
}

extension Debuggee.Image {
  internal var offsets: Debuggee.ImageOffsets {
    get throws(Debuggee.Error) {
      .segments(text: base, data: nil)
    }
  }
}

#endif
