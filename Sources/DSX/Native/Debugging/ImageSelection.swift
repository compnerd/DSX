// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(anyAppleOS)
extension ProcessIdentifier {
  internal func images(_ addresses: borrowing Span<UInt64>,
                       style: Debuggee.Image.Style)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
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
