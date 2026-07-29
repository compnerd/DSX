// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(anyAppleOS)
extension ProcessIdentifier {
  internal func loader(control _: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.Loader {
    try loader
  }

  internal func address(control _: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.Address {
    try address
  }

  internal func cache(control _: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.SharedCache {
    try cache
  }

  internal func image(control _: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.Image? {
    try image
  }

  internal func images(_ addresses: borrowing Span<UInt64>,
                       style: Debuggee.Image.Style,
                       control _: borrowing NativeDebugControl =
                           NativeDebugControl()) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    let loaded = try images(style)
    var images = Array<Debuggee.Image>()
    images.reserveCapacity(addresses.count)
    for index in 0 ..< addresses.count {
      if let image = loaded.first(where: { image in
        image.base.rawValue == addresses[index]
      }) {
        images.append(image)
      }
    }
    return images
  }
}
#endif
