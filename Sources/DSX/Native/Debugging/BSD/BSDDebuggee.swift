// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal struct BSDImageCursor {
  internal init(_: ProcessIdentifier, svr4 _: Bool) throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Image? {
    throw .unsupported
  }
}

extension Debuggee.Image {
  internal var offsets: Debuggee.ImageOffsets {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}

extension ProcessIdentifier {
  internal var address: Debuggee.Address {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal var image: Debuggee.Image? {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal func images(_ style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    throw .unsupported
  }

  internal var linkage: Array<Debuggee.Image> {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal var cache: Debuggee.SharedCache {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}

#endif
