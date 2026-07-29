// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(anyAppleOS)
internal import Darwin
#elseif os(Windows)
internal import WinSDK
#endif

@Suite
internal struct ProcessInfoTests {
#if os(anyAppleOS)
  @Test
  internal func native() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let info = try process.info
    var architecture = proc_archinfo()
    let size = MemoryLayout<proc_archinfo>.size
    let count =
        proc_pidinfo(getpid(), Darwin.PROC_PIDARCHINFO, 0, &architecture,
                     Int32(size))
    try #require(count == size)
    let cpu = UInt64(UInt32(bitPattern: architecture.p_cputype))
    let subtype = UInt64(UInt32(bitPattern: architecture.p_cpusubtype))
    #expect(info.cpu == cpu)
    #expect(info.subtype == subtype)
    #expect(info.system == Host.metadata.system?.description)
  }
#endif

  @Test
  internal func matching() {
    let names = [
      "", "a", "A", "ab", "aB", "/tmp/program", "program", "c:/Program.exe",
      "C:\\program.exe", "é", "É", "e\u{301}", "日本語", "日本語/program",
    ]
    for name in names {
      let info = Debuggee.Process.Info(process: ProcessIdentifier(rawValue: 1),
                                       parent: nil, name: name,
                                       architecture: "")
      for candidate in names {
#if os(Windows)
        let source = String(name.map { $0 == "\\" ? "/" : $0 })
        let comparison = String(candidate.map { $0 == "\\" ? "/" : $0 })
        let expected = source.withCString(encodedAs: UTF16.self) { lhs in
          comparison.withCString(encodedAs: UTF16.self) { rhs in
            CompareStringOrdinal(lhs, CInt(source.utf16.count), rhs,
                                 CInt(comparison.utf16.count), true)
                == WinSDK.CSTR_EQUAL
          }
        }
#else
        let expected = if let separator = name.lastIndex(of: "/") {
          name == candidate ||
              name[name.index(after: separator)...] == candidate
        } else {
          name == candidate
        }
#endif
        #expect(info.matches(candidate) == expected)
      }
    }
  }
}
