// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
#if os(Windows)
internal import WinSDK
#endif
@testable internal import DSX

@Suite(.serialized)
internal struct EnvironmentTests {
  @Test
  internal func bytes() throws {
    #if os(Windows)
    let unit: NativeEnvironment.Unit = 0xd800
    #else
    let unit: NativeEnvironment.Unit = 0xff
    #endif
    let inherited: Array<NativeEnvironment.Unit> = [65, 61, unit, 0]
    let changes = [Debuggee.Environment(name: "B", value: "")]
    let block =
        try ProcessEnvironment.resolve(changes.span, inheriting: inherited)
    #expect(block == inherited + [66, 61, 0, 0])
  }

  @Test
  internal func empty() throws {
    let changes = [Debuggee.Environment(name: "A", value: nil)]
    let inherited: Array<NativeEnvironment.Unit> = [65, 61, 66, 0]
    let block =
        try ProcessEnvironment.resolve(changes.span, inheriting: inherited)
    #expect(block == [0, 0])
  }

  @Test
  internal func replacement() throws {
    var inherited = Array<NativeEnvironment.Unit>()
    for entry in ["AB=prefix", "A=old", "A=duplicate", "C=untouched"] {
      NativeEnvironment.encode(entry, into: &inherited)
      inherited.append(0)
    }
    let changes = [
      Debuggee.Environment(name: "A", value: nil),
      Debuggee.Environment(name: "AB", value: "new"),
      Debuggee.Environment(name: "A", value: "last"),
      Debuggee.Environment(name: "AB", value: nil),
    ]
    let block =
        try ProcessEnvironment.resolve(changes.span, inheriting: inherited)
    let expected = [Debuggee.Environment(name: "A", value: "last"),
                    Debuggee.Environment(name: "C", value: "untouched")]
    #expect(decode(block) == expected)
  }

  @Test
  internal func unterminated() {
    let changes = Array<Debuggee.Environment>()
    let inherited: Array<NativeEnvironment.Unit> = [65, 61, 66]
    #expect(throws: Debuggee.Error.state) {
      _ = try ProcessEnvironment.resolve(changes.span, inheriting: inherited)
    }
  }

  @Test
  internal func nul() {
    let entry = Debuggee.Environment(name: "A", value: "B\0C")
    #expect(entry.valid == false)
  }

  @Test
  internal func inherit() throws {
    let inherited = try decode(NativeEnvironment.read())
    let changes = [Debuggee.Environment(name: "DSX_ENVIRONMENT_TEST",
                                        value: "child")]
    let values = try resolve(changes.span)
    for entry in inherited where entry.name != "DSX_ENVIRONMENT_TEST" {
      #expect(values.contains(entry))
    }
    #expect(values.contains(changes[0]))
  }

  @Test
  internal func overrides() throws {
    let changes = [
      Debuggee.Environment(name: "DSX_ENVIRONMENT_TEST", value: "first"),
      Debuggee.Environment(name: "DSX_ENVIRONMENT_TEST", value: nil),
      Debuggee.Environment(name: "DSX_ENVIRONMENT_TEST", value: "last"),
    ]
    let values = try resolve(changes.span)
    let entries = values.filter { $0.name == "DSX_ENVIRONMENT_TEST" }
    #expect(entries == [changes[2]])
  }

  @Test
  internal func unset() throws {
    let inherited = try decode(NativeEnvironment.read())
    let entry = try #require(inherited.first { !$0.name.contains("=") })
    let changes = [Debuggee.Environment(name: entry.name, value: nil)]
    let values = try resolve(changes.span)
    #expect(values.contains { $0.name == entry.name } == false)
    #expect(values.contains(entry) == false)
    #expect(try decode(NativeEnvironment.read()) == inherited)
  }

  @Test(arguments: ["", "A=B", "A\0B"])
  internal func invalid(_ name: String) {
    let changes = [Debuggee.Environment(name: name, value: "value")]
    #expect(throws: Debuggee.Error.state) {
      _ = try resolve(changes.span)
    }
  }

  #if os(Windows)
  @Test
  internal func lookup() throws {
    let name = "DSX_LOOKUP_\(GetCurrentProcessId())"
    defer {
      _ = withUTF16CString(name) { SetEnvironmentVariableW($0, nil) }
    }
    for value in ["", "é", String(repeating: "value", count: 2048)] {
      let set = withUTF16CString(name) { name in
        withUTF16CString(value) { SetEnvironmentVariableW(name, $0) }
      }
      #expect(set)
      #expect(try WindowsEnvironment[name] == value)
    }
    #expect(withUTF16CString(name) { SetEnvironmentVariableW($0, nil) })
    let error = Debuggee.Error.system(CInt(ERROR_ENVVAR_NOT_FOUND))
    #expect(throws: error) {
      _ = try WindowsEnvironment[name]
    }
  }

  @Test
  internal func drives() throws {
    var inherited = Array<NativeEnvironment.Unit>()
    NativeEnvironment.encode("=C:=C:\\directory", into: &inherited)
    inherited.append(0)
    let changes = [Debuggee.Environment(name: "A", value: "B")]
    let block =
        try ProcessEnvironment.resolve(changes.span, inheriting: inherited)
    #expect(block == inherited + [65, 61, 66, 0, 0])
  }

  @Test
  internal func unicode() throws {
    let changes = [Debuggee.Environment(name: "é", value: "first"),
                   Debuggee.Environment(name: "É", value: "last")]
    let block = try ProcessEnvironment.resolve(changes.span, inheriting: [])
    #expect(decode(block) == [changes[1]])
  }

  @Test
  internal func casing() throws {
    let changes = [
      Debuggee.Environment(name: "DSX_ENVIRONMENT_TEST", value: "first"),
      Debuggee.Environment(name: "dsx_environment_test", value: "last"),
    ]
    let values = try resolve(changes.span)
    #expect(values.contains(changes[1]))
    #expect(values.contains(changes[0]) == false)
    for index in 1 ..< values.count {
      #expect(Host.precedes(values[index - 1].name, values[index].name))
    }
  }
  #endif
}

private func resolve(_ changes: borrowing Span<Debuggee.Environment>)
    throws(Debuggee.Error) -> Array<Debuggee.Environment> {
  try decode(ProcessEnvironment.resolve(changes,
                                        inheriting: NativeEnvironment.read()))
}

private func decode(_ bytes: Array<NativeEnvironment.Unit>)
    -> Array<Debuggee.Environment> {
  bytes.split(separator: 0).compactMap { bytes in
    #if os(Windows)
    let entry = String(decoding: bytes, as: UTF16.self)
    #else
    let entry = String(decoding: bytes, as: UTF8.self)
    #endif
    guard let separator = entry.dropFirst().firstIndex(of: "=") else {
      return nil
    }
    let name = String(entry[..<separator])
    let value = String(entry[entry.index(after: separator)...])
    return Debuggee.Environment(name: name, value: value)
  }
}
