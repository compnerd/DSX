// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import MachO

internal struct DarwinImageCursor {
  private var images: IndexingIterator<Array<Debuggee.Image>>

  internal init(_ process: ProcessIdentifier, svr4: Bool)
      throws(Debuggee.Error) {
    images = try (svr4 ? process.linkage : process.images(.name)).makeIterator()
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

extension ProcessIdentifier {
  internal var executed: Bool {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      return try DSX::snapshot(task.handle).infoArrayCount == 0
    }
  }

  internal var address: Debuggee.Address {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      let info = try DSX::info(task.handle)
      return Debuggee.Address(rawValue: info.all_image_info_addr)
    }
  }

  internal func images(_ style: Debuggee.Image.Style) throws(Debuggee.Error)
      -> Array<Debuggee.Image> {
    try DSX::images(self, described: style.described)
  }

  internal func images(_ addresses: borrowing Span<UInt64>,
                       style: Debuggee.Image.Style)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
    let task = try DarwinTask(self)
    let registered = try DSX::images(self, described: style.described)
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
        let details: Debuggee.ImageDescription? = if style.described {
          try description(task.handle, address: address)
        } else {
          nil
        }
        let system = try DSX::platform(task.handle, address: address)
        images.append(Debuggee.Image(path: "",
                                     base: Debuggee.Address(rawValue: address),
                                     system: system, description: details))
      } catch {
        continue
      }
    }
    return images
  }

  internal var linkage: Array<Debuggee.Image> {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }

  internal var cache: Debuggee.SharedCache {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      let all = try DSX::snapshot(task.handle)
      let identifier = format(all.sharedCacheUUID)
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
      let all = try DSX::snapshot(task.handle)
      let records = array(all)
      guard records.count > 0 else {
        return nil
      }
      return try DSX::image(task.handle, records: records, index: 0,
                            described: false)
    }
  }

  internal var header: Debuggee.ImageHeader? {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      guard let base = try executable(task.handle) else {
        return nil
      }
      return try description(task.handle, address: base.rawValue).header
    }
  }

  internal var platform: String? {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      guard let base = try executable(task.handle) else {
        return nil
      }
      return try DSX::platform(task.handle, address: base.rawValue)
    }
  }
}

private func path() -> String? {
  guard let symbol = dlsym(kRTLDDefault, "dyld_shared_cache_file_path") else {
    return nil
  }
  typealias Query = @convention(c) () -> UnsafePointer<CChar>?
  let query = unsafeBitCast(symbol, to: Query.self)
  guard let path = query() else {
    return nil
  }
  return String(cString: path)
}

private func images(_ process: ProcessIdentifier, described: Bool)
    throws(Debuggee.Error) -> Array<Debuggee.Image> {
  let task = try DarwinTask(process)
  let all = try snapshot(task.handle)
  let records = array(all)
  if records.count == 0, let base = try executable(task.handle) {
    let info = try process.info
    let system = try platform(task.handle, address: base.rawValue)
    let details: Debuggee.ImageDescription? = if described {
      try description(task.handle, address: base.rawValue)
    } else {
      nil
    }
    var images = [
      Debuggee.Image(path: info.name, base: base, main: true, system: system,
                     description: details),
    ]
    if let base = try loader(task.handle, all) {
      let system = try platform(task.handle, address: base.rawValue)
      let details: Debuggee.ImageDescription? = if described {
        try description(task.handle, address: base.rawValue)
      } else {
        nil
      }
      images.append(Debuggee.Image(path: "/usr/lib/dyld", base: base,
                                   main: false, system: system,
                                   description: details))
    }
    return images
  }
  var images = Array<Debuggee.Image>()
  images.reserveCapacity(records.count + 1)
  for index in 0 ..< records.count {
    try images.append(image(task.handle, records: records, index: index,
                            described: described))
  }
  if let base = try loader(task.handle, all) {
    for image in images where image.base == base {
      return images
    }
    let system = try platform(task.handle, address: base.rawValue)
    let details: Debuggee.ImageDescription? = if described {
      try description(task.handle, address: base.rawValue)
    } else {
      nil
    }
    images.append(Debuggee.Image(path: "/usr/lib/dyld", base: base, main: false,
                                 system: system, description: details))
  }
  return images
}

private func snapshot(_ task: mach_port_name_t) throws(Debuggee.Error)
    -> dyld_all_image_infos {
  let info = try info(task)
  var all = dyld_all_image_infos()
  try read(task, address: info.all_image_info_addr, into: &all)
  return all
}

private func loader(_ task: mach_port_name_t,
                    _ all: borrowing dyld_all_image_infos)
    throws(Debuggee.Error) -> Debuggee.Address? {
  let address = UInt64(UInt(bitPattern: all.dyldImageLoadAddress))
  if address > 0 {
    var header = mach_header_64()
    do throws(Debuggee.Error) {
      try read(task, address: address, into: &header)
      if header.magic == MH_MAGIC_64, header.filetype == MH_DYLINKER {
        return Debuggee.Address(rawValue: address)
      }
    } catch {
    }
  }
  return try executable(task, file: UInt32(MH_DYLINKER))
}

private func image(_ task: mach_port_name_t,
                   records: (base: UInt64, count: Int), index: Int,
                   described: Bool) throws(Debuggee.Error) -> Debuggee.Image {
  var record = dyld_image_info()
  let stride = MemoryLayout<dyld_image_info>.stride
  let cursor = records.base + UInt64(index * stride)
  try read(task, address: cursor, into: &record)
  let address = UInt64(UInt(bitPattern: record.imageLoadAddress))
  let remote = UInt64(UInt(bitPattern: record.imageFilePath))
  let path = try string(task, address: remote)
  let system = try platform(task, address: address)
  let details: Debuggee.ImageDescription? = if described {
    try description(task, address: address)
  } else {
    nil
  }
  return Debuggee.Image(path: path, base: Debuggee.Address(rawValue: address),
                        main: index == 0, system: system, description: details)
}

private func description(_ task: mach_port_name_t, address: UInt64)
    throws(Debuggee.Error) -> Debuggee.ImageDescription {
  var header = mach_header_64()
  try read(task, address: address, into: &header)
  guard header.magic == MH_MAGIC_64 else {
    throw .state
  }
  var cursor = address + UInt64(MemoryLayout<mach_header_64>.size)
  var segments = Array<Debuggee.ImageSegment>()
  var identifier = ""
  for _ in 0 ..< header.ncmds {
    var command = load_command()
    try read(task, address: cursor, into: &command)
    guard command.cmdsize >= MemoryLayout<load_command>.size else {
      throw .state
    }
    switch command.cmd {
    case UInt32(LC_SEGMENT_64):
      var segment = segment_command_64()
      try read(task, address: cursor, into: &segment)
      let protection = UInt32(bitPattern: segment.maxprot)
      let image =
          Debuggee.ImageSegment(name: name(segment), address: segment.vmaddr,
                                size: segment.vmsize, offset: segment.fileoff,
                                bytes: segment.filesize, protection: protection)
      segments.append(image)
    case UInt32(LC_UUID):
      var uuid = uuid_command()
      try read(task, address: cursor, into: &uuid)
      identifier = format(uuid.uuid)
    default:
      break
    }
    guard cursor <= UInt64.max - UInt64(command.cmdsize) else {
      throw .state
    }
    cursor += UInt64(command.cmdsize)
  }
  let size = UInt32(MemoryLayout<mach_header_64>.size) + header.sizeofcmds
  let subtype = UInt32(bitPattern: header.cpusubtype) & ~kCPUSubtypeMask
  let result =
      Debuggee.ImageHeader(magic: header.magic,
                           cpu: UInt32(bitPattern: header.cputype),
                           subtype: subtype, file: header.filetype,
                           flags: header.flags, size: size)
  return Debuggee.ImageDescription(header: result, segments: segments,
                                   identifier: identifier)
}

private func info(_ task: mach_port_name_t) throws(Debuggee.Error)
    -> task_dyld_info_data_t {
  var info = task_dyld_info_data_t()
  let bytes = MemoryLayout<task_dyld_info_data_t>.size
  let size = bytes / MemoryLayout<natural_t>.size
  var count = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
      task_info(task, task_flavor_t(TASK_DYLD_INFO), info, &count)
    }
  }
  guard status == KERN_SUCCESS else {
    throw DarwinError.debuggee(status, invalid: .process)
  }
  return info
}

private func executable(_ task: mach_port_name_t,
                        file: UInt32 = UInt32(MH_EXECUTE))
    throws(Debuggee.Error) -> Debuggee.Address? {
  var address: mach_vm_address_t = 0
  var depth: natural_t = 0
  while true {
    var size: mach_vm_size_t = 0
    var info = vm_region_submap_info_64()
    let bytes = MemoryLayout<vm_region_submap_info_64>.size
    let words = bytes / MemoryLayout<integer_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &info) { info in
      info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
        mach_vm_region_recurse(task, &address, &size, &depth, info, &count)
      }
    }
    if status == KERN_INVALID_ADDRESS {
      return nil
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    if info.is_submap > 0 {
      depth += 1
      continue
    }
    if info.protection & VM_PROT_READ > 0 {
      var header = mach_header_64()
      try read(task, address: address, into: &header)
      if header.magic == MH_MAGIC_64, header.filetype == file {
        return Debuggee.Address(rawValue: address)
      }
    }
    guard size > 0, address <= mach_vm_address_t.max - size else {
      throw .state
    }
    address += size
  }
}

private func platform(_ task: mach_port_name_t, address: UInt64)
    throws(Debuggee.Error) -> String? {
  var header = mach_header_64()
  try read(task, address: address, into: &header)
  guard header.magic == MH_MAGIC_64 else {
    return nil
  }
  var cursor = address + UInt64(MemoryLayout<mach_header_64>.size)
  for _ in 0 ..< header.ncmds {
    var command = load_command()
    try read(task, address: cursor, into: &command)
    guard command.cmdsize >= MemoryLayout<load_command>.size else {
      throw .state
    }
    if command.cmd == LC_BUILD_VERSION {
      var version = build_version_command()
      try read(task, address: cursor, into: &version)
      return name(version.platform)
    }
    let legacy = legacy(command.cmd)
    if let legacy {
      return legacy
    }
    cursor += UInt64(command.cmdsize)
  }
  return nil
}

private func string(_ task: mach_port_name_t, address: UInt64)
    throws(Debuggee.Error) -> String {
  if address == 0 {
    return ""
  }
  var bytes = Array<UInt8>()
  bytes.reserveCapacity(256)
  var cursor = address
  while bytes.count < Int(PATH_MAX) {
    var byte: UInt8 = 0
    try read(task, address: cursor, into: &byte)
    if byte == 0 {
      break
    }
    bytes.append(byte)
    cursor += 1
  }
  return String(decoding: bytes, as: UTF8.self)
}

private func read<Value>(_ task: mach_port_name_t, address: UInt64,
                         into value: inout Value) throws(Debuggee.Error) {
  var count: mach_vm_size_t = 0
  let status = withUnsafeMutableBytes(of: &value) { buffer in
    let destination = UInt(bitPattern: buffer.baseAddress)
    return mach_vm_read_overwrite(task, mach_vm_address_t(address),
                                  mach_vm_size_t(buffer.count),
                                  mach_vm_address_t(destination), &count)
  }
  guard status == KERN_SUCCESS,
      count == mach_vm_size_t(MemoryLayout<Value>.size) else {
    throw DarwinError.debuggee(status, invalid: .process)
  }
}

private func array(_ all: borrowing dyld_all_image_infos)
    -> (base: UInt64, count: Int) {
  let base = UInt64(UInt(bitPattern: all.infoArray))
  return (base: base, count: Int(all.infoArrayCount))
}

private func name(_ segment: borrowing segment_command_64) -> String {
  withUnsafeBytes(of: segment.segname) { bytes in
    let count = bytes.firstIndex(of: 0) ?? bytes.count
    return String(decoding: bytes.prefix(count), as: UTF8.self)
  }
}

private func format(_ identifier: borrowing uuid_t) -> String {
  withUnsafeBytes(of: identifier) { bytes in
    var value = ""
    value.reserveCapacity(36)
    for index in 0 ..< bytes.count {
      if index == 4 || index == 6 || index == 8 || index == 10 {
        value.append("-")
      }
      let byte = bytes[index]
      value.append(Character(UnicodeScalar(hexadecimal(byte >> 4))))
      value.append(Character(UnicodeScalar(hexadecimal(byte))))
    }
    return value
  }
}

private func hexadecimal(_ value: UInt8) -> UInt8 {
  let value = value & 0x0f
  return if value < 10 {
    value + UInt8(ascii: "0")
  } else {
    value - 10 + UInt8(ascii: "A")
  }
}

private func legacy(_ command: UInt32) -> String? {
  switch command {
  case LC_VERSION_MIN_MACOSX:
    "macosx"
  case LC_VERSION_MIN_IPHONEOS:
    "ios"
  case LC_VERSION_MIN_TVOS:
    "tvos"
  case LC_VERSION_MIN_WATCHOS:
    "watchos"
  default:
    nil
  }
}

private func name(_ platform: UInt32) -> String? {
  switch platform {
  case PLATFORM_MACOS:
    "macosx"
  case PLATFORM_IOS:
    "ios"
  case PLATFORM_TVOS:
    "tvos"
  case PLATFORM_WATCHOS:
    "watchos"
  case PLATFORM_BRIDGEOS:
    "bridgeos"
  case PLATFORM_MACCATALYST:
    "maccatalyst"
  case PLATFORM_IOSSIMULATOR:
    "iossimulator"
  case PLATFORM_TVOSSIMULATOR:
    "tvossimulator"
  case PLATFORM_WATCHOSSIMULATOR:
    "watchossimulator"
  case PLATFORM_DRIVERKIT:
    "driverkit"
  default:
    nil
  }
}

#endif
