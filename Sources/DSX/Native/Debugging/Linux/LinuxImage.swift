// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
internal typealias LinuxImageCursor = IndexingIterator<Array<Debuggee.Image>>

extension LinuxImageCursor {
  internal init(_ process: ProcessIdentifier, svr4: Bool)
      throws(Debuggee.Error) {
    self = try (svr4 ? process.linkage : process.images(.name)).makeIterator()
  }
}

extension Debuggee.Image {
  internal var offsets: Debuggee.ImageOffsets {
    get throws(Debuggee.Error) {
      .segments(text: base, data: nil)
    }
  }
}

extension ProcessIdentifier {
  internal var address: Debuggee.Address {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal func images(_ style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    let identifier = try native
    let bytes = try LinuxProcFS.contents("/proc/\(identifier)/maps")
    var maps = LinuxMemoryMapReader(bytes.span)
    let executable = try? LinuxProcFS.link("/proc/\(identifier)/exe")
    var images = Array<Debuggee.Image>()
    while let map = maps.next() {
      guard maps.absolute(map), let path = maps.path(map) else {
        continue
      }
      let address = map.start.rawValue
      let base = address >= map.offset ? address - map.offset : address
      if let index = images.firstIndex(where: { image in
        image.path == path
      }) {
        if map.executable {
          images[index].sections.append(map.start)
        }
      } else {
        let sections = map.executable ? [map.start] : []
        images.append(Debuggee.Image(path: path,
                                     base: Debuggee.Address(rawValue: base),
                                     sections: sections,
                                     main: path == executable))
      }
    }
    return images
  }

  internal var linkage: Array<Debuggee.Image> {
    get throws(Debuggee.Error) {
      let identifier = try native
      return try LinuxSVR4.images(identifier, maps: images(.name))
    }
  }

  internal var image: Debuggee.Image? {
    get throws(Debuggee.Error) {
      let identifier = try native
      let bytes = try LinuxProcFS.contents("/proc/\(identifier)/maps")
      var maps = LinuxMemoryMapReader(bytes.span)
      let executable = try LinuxProcFS.link("/proc/\(identifier)/exe")
      while let map = maps.next() {
        guard maps.absolute(map), let path = maps.path(map),
            path == executable else {
          continue
        }
        let address = map.start.rawValue
        let base = address >= map.offset ? address - map.offset : address
        let sections = map.executable ? [map.start] : []
        return Debuggee.Image(path: path,
                              base: Debuggee.Address(rawValue: base),
                              sections: sections, main: true)
      }
      return nil
    }
  }

  internal var cache: Debuggee.SharedCache {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}
#endif
