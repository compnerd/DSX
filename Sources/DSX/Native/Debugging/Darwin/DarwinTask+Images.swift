// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import MachO

private var CPU_SUBTYPE_MASK: UInt32 { 0xff00_0000 }

extension ProcessIdentifier {
  internal var executed: Bool {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      return try task.snapshot().infoArrayCount == 0
    }
  }

  internal var address: Debuggee.Address {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      let info = try task.info()
      return Debuggee.Address(rawValue: info.all_image_info_addr)
    }
  }

  internal func images(_ style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    let task = try DarwinTask(self)
    return try task.images(self, described: style.described)
  }

  internal func images(_ addresses: borrowing Span<UInt64>,
                       style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    let task = try DarwinTask(self)
    let registered = try task.images(self, described: style.described)
    var images = Array<Debuggee.Image>()
    images.reserveCapacity(addresses.count)
    for index in 0 ..< addresses.count {
      let address = addresses[index]
      if let image = registered.first(where: { image in
        image.base.rawValue == address
      }) {
        images.append(image)
        continue
      }
      do throws(Debuggee.Error) {
        try images.append(task.image(address: address, path: "",
                                     described: style.described))
      } catch {
        continue
      }
    }
    return images
  }

  internal var cache: Debuggee.SharedCache {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      let all = try task.snapshot(version: 15)
      let identifier = withUnsafeBytes(of: all.sharedCacheUUID) { bytes in
        String(uuid: bytes.bindMemory(to: UInt8.self).span)
      }
      let base = Debuggee.Address(rawValue: UInt64(all.sharedCacheBaseAddress))
      let absent = all.sharedCacheBaseAddress == 0 || identifier.allSatisfy {
        $0 == "0" || $0 == "-"
      }
      return Debuggee.SharedCache(base: base, identifier: identifier,
                                  absent: absent, isolated: false, path: path())
    }
  }

  internal var image: Debuggee.Image? {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      let all = try task.snapshot()
      let records = try all.records
      guard records.count > 0 else {
        return nil
      }
      return try task.image(records: records, index: 0, described: false)
    }
  }
}

private func path() -> String? {
  guard let symbol = dlsym(RTLD_DEFAULT, "dyld_shared_cache_file_path") else {
    return nil
  }
  typealias Query = @convention(c) () -> UnsafePointer<CChar>?
  let query = unsafeBitCast(symbol, to: Query.self)
  guard let path = query() else {
    return nil
  }
  return String(cString: path)
}

extension DarwinTask {
  fileprivate func images(_ process: ProcessIdentifier, described: Bool)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
    let all = try snapshot()
    let records = try all.records
    if records.count == 0, let base = try executable() {
      let info = try process.info
      var images = [
        try image(address: base.rawValue, path: info.name, main: true,
                  described: described),
      ]
      if let base = try loader(all) {
        try images.append(image(address: base.rawValue, path: "/usr/lib/dyld",
                                described: described))
      }
      return images
    }
    var images = Array<Debuggee.Image>()
    images.reserveCapacity(records.count + 1)
    for index in 0 ..< records.count {
      try images.append(image(records: records, index: index,
                              described: described))
    }
    if let base = try loader(all) {
      for image in images where image.base == base {
        return images
      }
      try images.append(image(address: base.rawValue, path: "/usr/lib/dyld",
                              described: described))
    }
    return images
  }

  fileprivate func snapshot(version: UInt32 = 2) throws(Debuggee.Error)
      -> dyld_all_image_infos {
    typealias Layout = MemoryLayout<dyld_all_image_infos>
    let info = try info()
    guard info.all_image_info_format == TASK_DYLD_ALL_IMAGE_INFO_64 else {
      throw .unsupported
    }
    let field = version >= 15 ? Layout.offset(of: \.sharedCacheBaseAddress)!
        : Layout.offset(of: \.dyldImageLoadAddress)!
    let required = UInt64(field + MemoryLayout<UInt>.size)
    guard info.all_image_info_size >= required else {
      throw .process
    }
    var all = dyld_all_image_infos()
    try withUnsafeMutableBytes(of: &all) { bytes throws(Debuggee.Error) in
      let count = min(UInt64(bytes.count), info.all_image_info_size)
      let buffer = UnsafeMutableRawBufferPointer(rebasing: bytes[..<Int(count)])
      try read(address: info.all_image_info_addr, into: buffer)
    }
    guard all.version >= version else {
      throw .unsupported
    }
    return all
  }

  private func loader(_ all: borrowing dyld_all_image_infos)
      throws(Debuggee.Error) -> Debuggee.Address? {
    let address = UInt64(UInt(bitPattern: all.dyldImageLoadAddress))
    if address > 0 {
      var header = mach_header_64()
      do throws(Debuggee.Error) {
        try read(address: address, into: &header)
        if header.magic == MH_MAGIC_64, header.filetype == MH_DYLINKER {
          return Debuggee.Address(rawValue: address)
        }
      } catch {
      }
    }
    return try executable(file: UInt32(MH_DYLINKER))
  }

  fileprivate func image(records: (base: UInt64, count: Int), index: Int,
                         described: Bool) throws(Debuggee.Error)
      -> Debuggee.Image {
    var record = dyld_image_info()
    let stride = MemoryLayout<dyld_image_info>.stride
    let offset = UInt64(index) * UInt64(stride)
    guard offset <= UInt64.max - records.base else {
      throw .process
    }
    let cursor = records.base + offset
    try read(address: cursor, into: &record)
    let address = UInt64(UInt(bitPattern: record.imageLoadAddress))
    let remote = UInt64(UInt(bitPattern: record.imageFilePath))
    let path = try string(address: remote)
    return try image(address: address, path: path, main: index == 0,
                     described: described)
  }

  fileprivate func image(address: UInt64, path: String, main: Bool = false,
                         described: Bool) throws(Debuggee.Error)
      -> Debuggee.Image {
    var header = mach_header_64()
    try read(address: address, into: &header)
    let base = Debuggee.Address(rawValue: address)
    guard header.magic == MH_MAGIC_64 else {
      if described {
        throw .state
      }
      return Debuggee.Image(path: path, base: base, main: main)
    }
    let size = try header.extent
    guard UInt64(size) <= UInt64.max - address else {
      throw .process
    }
    var cursor = address + UInt64(MemoryLayout<mach_header_64>.size)
    let end = address + UInt64(size)
    var segments = Array<Debuggee.ImageSegment>()
    var identifier = ""
    var system: String?
    var identified = false
    for _ in 0 ..< header.ncmds {
      if identified, described == false {
        break
      }
      guard end - cursor >= MemoryLayout<load_command>.size else {
        throw .process
      }
      var command = load_command()
      try read(address: cursor, into: &command)
      let validated = try MachOLoadCommand(command.cmd, size: command.cmdsize,
                                           remaining: end - cursor)
      if identified == false {
        if command.cmd == LC_BUILD_VERSION {
          var version = build_version_command()
          try read(address: cursor, into: &version)
          system = String(platform: version.platform)
          identified = true
        } else if let platform = validated.platform {
          system = String(platform: platform)
          identified = system != nil
        }
      }
      switch command.cmd {
      case LC_SEGMENT_64 where described:
        var segment = segment_command_64()
        try read(address: cursor, into: &segment)
        let protection = UInt32(bitPattern: segment.maxprot)
        let image =
            Debuggee.ImageSegment(name: segment.name, address: segment.vmaddr,
                                  size: segment.vmsize, offset: segment.fileoff,
                                  bytes: segment.filesize,
                                  protection: protection)
        segments.append(image)
      case LC_UUID where described:
        var uuid = uuid_command()
        try read(address: cursor, into: &uuid)
        identifier = withUnsafeBytes(of: uuid.uuid) { bytes in
          String(uuid: bytes.bindMemory(to: UInt8.self).span)
        }
      default:
        break
      }
      cursor += UInt64(command.cmdsize)
    }
    guard described else {
      return Debuggee.Image(path: path, base: base, main: main, system: system)
    }
    let subtype = UInt32(bitPattern: header.cpusubtype) & ~CPU_SUBTYPE_MASK
    let result =
        Debuggee.ImageHeader(magic: header.magic,
                             cpu: UInt32(bitPattern: header.cputype),
                             subtype: subtype, file: header.filetype,
                             flags: header.flags, size: size)
    let details = Debuggee.ImageDescription(header: result, segments: segments,
                                            identifier: identifier)
    return Debuggee.Image(path: path, base: base, main: main, system: system,
                          description: details)
  }

  fileprivate func info() throws(Debuggee.Error) -> task_dyld_info_data_t {
    var info = task_dyld_info_data_t()
    let bytes = MemoryLayout<task_dyld_info_data_t>.size
    let size = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &info) { info in
      info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
        task_info(handle, task_flavor_t(TASK_DYLD_INFO), info, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    return info
  }

  private func executable(file: UInt32 = UInt32(MH_EXECUTE))
      throws(Debuggee.Error) -> Debuggee.Address? {
    var address: mach_vm_address_t = 0
    var depth: natural_t = 0
    while let mapping =
        try mapping(at: address, depth: &depth, invalid: .process) {
      address = mapping.address
      let size = mapping.size
      if mapping.protection & VM_PROT_READ > 0 {
        var header = mach_header_64()
        try read(address: address, into: &header)
        if header.magic == MH_MAGIC_64, header.filetype == file {
          return Debuggee.Address(rawValue: address)
        }
      }
      guard size > 0, address <= mach_vm_address_t.max - size else {
        throw .state
      }
      address += size
    }
    return nil
  }

  private func string(address: UInt64) throws(Debuggee.Error) -> String {
    if address == 0 {
      return ""
    }
    var bytes = Array<UInt8>()
    bytes.reserveCapacity(256)
    var buffer = InlineArray<256, UInt8> { _ in 0 }
    let page = UInt64(getpagesize())
    var cursor = address
    while bytes.count < Int(PATH_MAX) {
      let boundary = Int(page - cursor % page)
      let count = min(buffer.count, boundary, Int(PATH_MAX) - bytes.count)
      try withUnsafeMutableBytes(of: &buffer) { buffer throws(Debuggee.Error) in
        let chunk = UnsafeMutableRawBufferPointer(rebasing: buffer[..<count])
        try read(address: cursor, into: chunk)
      }
      for index in 0 ..< count {
        if buffer[index] == 0 {
          return String(decoding: bytes, as: UTF8.self)
        }
        bytes.append(buffer[index])
      }
      guard UInt64(count) <= UInt64.max - cursor else {
        throw .process
      }
      cursor += UInt64(count)
    }
    throw .process
  }

  private func read<Value>(address: UInt64,
                           into value: inout Value) throws(Debuggee.Error) {
    try withUnsafeMutableBytes(of: &value) { bytes throws(Debuggee.Error) in
      try read(address: address, into: bytes)
    }
  }

  private func read(address: UInt64, into buffer: UnsafeMutableRawBufferPointer)
      throws(Debuggee.Error) {
    var count: mach_vm_size_t = 0
    let destination = UInt(bitPattern: buffer.baseAddress)
    let status =
        mach_vm_read_overwrite(handle, mach_vm_address_t(address),
                               mach_vm_size_t(buffer.count),
                               mach_vm_address_t(destination), &count)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    guard count == buffer.count else {
      throw .process
    }
  }
}

extension dyld_all_image_infos {
  fileprivate var records: (base: UInt64, count: Int) {
    get throws(Debuggee.Error) {
      // dyld clears infoArray while updating it; a stopped task cannot retry.
      guard infoArray != nil || infoArrayCount == 0 else {
        throw .state
      }
      let base = UInt64(UInt(bitPattern: infoArray))
      return (base: base, count: Int(infoArrayCount))
    }
  }
}

extension segment_command_64 {
  fileprivate var name: String {
    withUnsafeBytes(of: segname) { bytes in
      let count = bytes.firstIndex(of: 0) ?? bytes.count
      return String(decoding: bytes.prefix(count), as: UTF8.self)
    }
  }
}

extension mach_header_64 {
  fileprivate var extent: UInt32 {
    get throws(Debuggee.Error) {
      let header = UInt32(MemoryLayout<mach_header_64>.size)
      guard sizeofcmds <= UInt32.max - header, ncmds <= sizeofcmds / 8 else {
        throw .process
      }
      return header + sizeofcmds
    }
  }
}

#endif
