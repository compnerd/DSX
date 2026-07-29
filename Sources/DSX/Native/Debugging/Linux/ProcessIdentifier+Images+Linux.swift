// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif


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
    var images = Array<(image: Debuggee.Image, end: UInt64?)>()
    while let map = maps.next() {
      guard maps.absolute(map), let path = maps.path(map) else {
        continue
      }
      let address = map.start.rawValue
      let base = address >= map.offset ? address - map.offset : address
      if let index = images.lastIndex(where: { entry in
        entry.image.base.rawValue <= address &&
            (entry.end.map { address < $0 } ?? (map.offset > 0)) &&
            entry.image.path.matches(utf8: path)
      }) {
        if map.executable {
          images[index].image.sections.append(map.start)
        }
      } else {
        let path = String(decoding: path, as: UTF8.self)
        let sections = map.executable ? [map.start] : []
        let image = Debuggee.Image(path: path,
                                   base: Debuggee.Address(rawValue: base),
                                   sections: sections, main: path == executable)
        let end = try? extent(map, path: path)
        images.append((image, end))
      }
    }
    return images.map(\.image)
  }

  private func extent(_ map: LinuxMemoryMap, path: String)
      throws(Debuggee.Error) -> UInt64 {
    // A load's PT_LOAD extent includes segment gaps and RELRO remappings.
    // Distinct loads may share a pathname, but never the same address range.
    guard map.offset == 0 else {
      throw .unsupported
    }
    let identifier = try native
    let start = String(map.start.rawValue, radix: 16)
    let end = String(map.end.rawValue, radix: 16)
    let file: UnixMappedFile
    do {
      file = try UnixMappedFile("/proc/\(identifier)/map_files/\(start)-\(end)")
    } catch {
      file = try UnixMappedFile("/proc/\(identifier)/root\(path)")
    }
    guard let module = try ELFModule(file.span()) else {
      throw .process
    }
    let extent = try module.extent
    let page = UInt64(getpagesize())
    let origin = extent.lowerBound - extent.lowerBound % page
    let (limit, overflow) =
        map.start.rawValue.addingReportingOverflow(extent.upperBound - origin)
    guard overflow == false else {
      throw .process
    }
    return limit
  }

  internal var image: Debuggee.Image? {
    get throws(Debuggee.Error) {
      let identifier = try native
      let bytes = try LinuxProcFS.contents("/proc/\(identifier)/maps")
      var maps = LinuxMemoryMapReader(bytes.span)
      let executable = try LinuxProcFS.link("/proc/\(identifier)/exe")
      while let map = maps.next() {
        guard maps.absolute(map), let path = maps.path(map),
            executable.matches(utf8: path) else {
          continue
        }
        let address = map.start.rawValue
        let base = address >= map.offset ? address - map.offset : address
        let sections = map.executable ? [map.start] : []
        return Debuggee.Image(path: String(decoding: path, as: UTF8.self),
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
