// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux)
internal import Glibc
#endif

@Suite
internal struct ProcessLookupTests {
  @Test(arguments: [("/usr/bin/sleep", "sleep", true),
                    ("/usr/bin/sleep", "/usr/bin/sleep", true),
                    ("/usr/bin/sleep", "/tmp/sleep", false),
                    ("/usr/bin/sleep", "bin/sleep", false),
                    ("/usr/bin/sleep", "leep", false),
                    ("sleep", "sleep", true), ("sleep", "", false)])
  internal func names(_ fixture: (String, String, Bool)) {
    let (path, name, expected) = fixture
    let info = Debuggee.Process.Info(process: ProcessIdentifier(rawValue: 1),
                                     parent: nil, name: path,
                                     architecture: "unknown")
    #expect(info.matches(name: name) == expected)
  }

#if os(Windows)
  @Test
  internal func separators() {
    let info = Debuggee.Process.Info(process: ProcessIdentifier(rawValue: 1),
                                     parent: nil, name: #"C:\bin\sleep.exe"#,
                                     architecture: "unknown")
    #expect(info.matches(name: "sleep.exe"))
    #expect(info.matches(name: #"other\sleep.exe"#) == false)
  }
#endif

  @Test
  internal func identifier() throws {
    #expect(try ProcessIdentifier(resolving: "123").rawValue == 123)
  }

#if os(Windows) || os(anyAppleOS) || os(Android) || os(Linux)
  @Test
  internal func current() throws {
#if os(Windows)
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
#else
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
#endif
    let info = try process.info
    let component = try #require(info.name.split(separator: "/").last)
    var lookup = try ProcessLookup(String(component))
    var found = false
    while let candidate = try lookup.next() {
      found = found || candidate == process
    }
    #expect(found)
  }
#endif
}
