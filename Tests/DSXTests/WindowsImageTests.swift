// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsImageTests {
  @Test
  internal func offsets() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let images = try process.images(.full)
    let image = try #require(images.first(where: { image in image.main }))
    let result = try process.image
    let selected = try #require(result)
    #expect(selected.path == image.path)
    #expect(selected.base == image.base)
    let info = try process.info
    let module = try Debuggee.Module(path: image.path)
    #expect(module.architecture == info.architecture)
    #expect(module.identity?.value.isEmpty == false)
    let storage = try NativeMappedFile(image.path)
    guard let view = try PEModule(storage.span()) else {
      Issue.record("expected a PE image")
      return
    }
    let preferred = try view.base
    let offsets = try image.offsets
    guard case .sections(let text, let data) = offsets else {
      Issue.record("Windows image offsets must use section relocation")
      return
    }
    #expect(text == image.base.rawValue &- preferred)
    #expect(data == text)
  }

  @Test
  internal func address() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let address = try process.address
    #expect(address == Debuggee.Address(rawValue: 0))
  }
}
#endif
