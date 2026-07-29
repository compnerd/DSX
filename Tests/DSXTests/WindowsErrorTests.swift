// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsErrorTests {
  @Test
  internal func hresult() {
    let access = HRESULT(bitPattern: 0x80070005)
    #expect(Debuggee.Error(hresult: access) == .access)
    #expect(Debuggee.Error(hresult: HRESULT(bitPattern: 0x80070032))
        == .unsupported)
    #expect(Debuggee.Error(hresult: HRESULT(bitPattern: 0x800700ce))
        == .system(CInt(DSX::ERROR_FILENAME_EXCED_RANGE)))
    let failure = HRESULT(bitPattern: 0x80004005)
    #expect(Debuggee.Error(hresult: failure) == .system(CInt(failure)))
  }

  @Test
  internal func capacity() throws {
    #expect(try WindowsPath.count(0) == 1)
    #expect(try WindowsPath.count(Int(PATHCCH_MAX_CCH)) == PATHCCH_MAX_CCH)
    let failure = Debuggee.Error.system(CInt(DSX::ERROR_FILENAME_EXCED_RANGE))
    #expect(throws: failure) {
      try WindowsPath.count(Int(PATHCCH_MAX_CCH) + 1)
    }
  }
}
#endif
