// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxProcessStatusTests {
  @Test
  internal func fields() throws {
    let bytes = Array("123 (name (with) spaces)) S 42 0 0\n".utf8)
    guard let status = LinuxProcessStatus(bytes.span) else {
      Issue.record("Missing process status")
      return
    }
    #expect(status.state == UInt8(ascii: "S"))
    #expect(status.parent == 42)
  }

  @Test
  internal func truncated() throws {
    for text in ["", "123 (name", "123 (name)", "123 (name) "] {
      let bytes = Array(text.utf8)
      let rejected = LinuxProcessStatus(bytes.span) == nil
      #expect(rejected)
    }
    for text in ["123 (name) Z", "123 (name) Z ", "123 (name) Z bad"] {
      let bytes = Array(text.utf8)
      guard let status = LinuxProcessStatus(bytes.span) else {
        Issue.record("Missing thread state")
        return
      }
      #expect(status.state == UInt8(ascii: "Z"))
      #expect(status.parent == nil)
    }
  }
}
#endif
