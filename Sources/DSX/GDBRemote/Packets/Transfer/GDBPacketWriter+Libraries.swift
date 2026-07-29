// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func transfer(_ process: ProcessIdentifier, offset: UInt64,
                                  length: UInt64, svr4: Bool,
                                  control: borrowing NativeDebugControl,
                                  executable: String?) throws(GDBHandlerError) {
    try transfer(offset: offset,
                 length: length) { emitter throws(Debuggee.Error) in
      if svr4 {
        var libraries = try NativeLibraryCursor(process)
        emitter.append("<?xml version=\"1.0\"?>")
        emitter.append("<library-list-svr4 version=\"1.0\">")
        while emitter.more == false, let library = try libraries.next() {
          try emitter.emit(library)
        }
      } else {
        var images = try control.images(process)
        emitter.append("<?xml version=\"1.0\"?><library-list>")
        while emitter.more == false, let image = try images.next() {
          try emitter.emit(image, executable: executable)
        }
      }
      if emitter.more == false {
        emitter.append(svr4 ? "</library-list-svr4>" : "</library-list>")
      }
    }
  }
}

extension GDBTransferEmitter {
  fileprivate mutating func emit(_ library: borrowing Debuggee.Library)
      throws(Debuggee.Error) {
    append("<library name=\"")
    try path(library.path)
    append("\" lm=\"0x")
    hex(library.link.rawValue)
    append("\" l_addr=\"0x")
    hex(library.bias)
    append("\" l_ld=\"0x")
    hex(library.dynamic.rawValue)
    append("\"/>")
  }

  fileprivate mutating func emit(_ image: borrowing Debuggee.Image,
                                 executable: String?) throws(Debuggee.Error) {
    let path = image.main ? executable ?? image.path : image.path
    append("<library name=\"")
    try self.path(path)
    append("\">")
    if image.sections.isEmpty {
      append("<section address=\"0x")
      hex(image.base.rawValue)
      append("\"/>")
    } else {
      for section in image.sections {
        append("<section address=\"0x")
        hex(section.rawValue)
        append("\"/>")
      }
    }
    append("</library>")
  }
}
