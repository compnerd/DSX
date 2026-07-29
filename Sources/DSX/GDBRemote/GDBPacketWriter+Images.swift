// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func emit(_ image: borrowing Debuggee.ImageDescription,
                              style: Debuggee.Image.Style = .full)
      throws(GDBHandlerError) {
    if style == .full {
      let header = image.header
      try append(",\"mach_header\":{\"magic\":")
      try decimal(UInt64(header.magic))
      try append(",\"cputype\":")
      try decimal(UInt64(header.cpu))
      try append(",\"cpusubtype\":")
      try decimal(UInt64(header.subtype))
      try append(",\"filetype\":")
      try decimal(UInt64(header.file))
      try append(",\"flags\":")
      try decimal(UInt64(header.flags))
      try append(",\"sizeof_mh_and_loadcmds\":")
      try decimal(UInt64(header.size))
      try append("},\"segments\":[")
      for index in 0 ..< image.segments.count {
        if index > 0 {
          try append(UInt8(ascii: ","))
        }
        let segment = image.segments[index]
        try append("{\"name\":\"")
        try json(segment.name)
        try append("\",\"vmaddr\":")
        try decimal(segment.address)
        try append(",\"vmsize\":")
        try decimal(segment.size)
        try append(",\"fileoff\":")
        try decimal(segment.offset)
        try append(",\"filesize\":")
        try decimal(segment.bytes)
        try append(",\"maxprot\":")
        try decimal(UInt64(segment.protection))
        try append(UInt8(ascii: "}"))
      }
      try append(UInt8(ascii: "]"))
    }
    try append(",\"uuid\":\"")
    try json(image.identifier)
    try append(UInt8(ascii: "\""))
  }
}
