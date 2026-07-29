// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsStringTests {
  @Test(arguments: ["", "ASCII", "a\0b", "路径/😀/e\u{301}",
                    String(repeating: "x", count: 259),
                    String(repeating: "x", count: 260),
                    String(repeating: "😀", count: 4096)])
  internal func encoding(_ value: String) {
    let expected = Array(value.utf16) + [0]
    let matched: Bool = withUTF16CString(value) { pointer in
      Array(UnsafeBufferPointer(start: pointer, count: expected.count))
          == expected
    }
    #expect(matched)
  }

  @Test
  internal func results() {
    let signed: CInt = withUTF16CString("value") { _ in CInt.min }
    let unsigned: DWORD = withUTF16CString("value") { _ in DWORD.max }
    let absent: HANDLE? = withUTF16CString("value") { _ in nil as HANDLE? }
    let expected = HANDLE(bitPattern: 0x1234)
    let present: HANDLE? = withUTF16CString("value") { _ in expected }
    #expect(signed == CInt.min)
    #expect(unsigned == DWORD.max)
    #expect(absent == nil)
    #expect(present == expected)
  }
}
#endif
