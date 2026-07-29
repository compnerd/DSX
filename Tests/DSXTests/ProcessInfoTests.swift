// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct ProcessInfoTests {
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
        let source = name.lowercased().map { $0 == "\\" ? "/" : $0 }
        let comparison = candidate.lowercased().map { $0 == "\\" ? "/" : $0 }
        let expected = String(source) == String(comparison)
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
