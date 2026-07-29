// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable import DSXCodeGen
import Testing

private let kInvalidProfiles: Array<(String, String)> = [
  ("unknown", kValidProfile
    .replacingOccurrences(of: "layout: fixed",
                          with: "layout: fixed\nunknown: value")),
  ("identifier", kValidProfile
    .replacingOccurrences(of: "id: 0\n    name: r0",
                          with: "id: 65536\n    name: r0")),
  ("size", kValidProfile
    .replacingOccurrences(of: "bits: 64", with: "bits: 7")),
  ("width", kValidProfile
    .replacingOccurrences(of: "bits: 64", with: "bits: 65536")),
  ("offset", kValidProfile
    .replacingOccurrences(of: "offset: 0", with: "offset: 65536")),
  ("number", kValidProfile
    .replacingOccurrences(of: "gdb: 0", with: "gdb: 32768")),
  ("set", kValidProfile
    .replacingOccurrences(of: "set: gpr", with: "set: absent")),
  ("feature", kValidProfile
    .replacingOccurrences(of: "feature: org.example.core",
                          with: "feature: org.example.absent")),
  ("type", kValidProfile
    .replacingOccurrences(of: "type: uint64", with: "type: absent")),
  ("relation", kValidProfile
    .replacingOccurrences(of: "invalidates: []",
                          with: "invalidates: [absent]")),
  ("scalable", kValidProfile
    .replacingOccurrences(of: "layout: fixed", with: "layout: scalable")),
]

@Suite
internal struct DSXCodeGenTests {
  @Test(arguments: ["argument0", "argument128", "argument255", "unknown"])
  internal func roles(_ role: String) {
    let source = kValidProfile
      .replacingOccurrences(of: "role: result", with: "role: \(role)")
    #expect(throws: DSXCodeGenError.self) { try decode(source) }
  }

  @Test(arguments: [("encoding: unsigned", "encoding: unknown"),
                    ("format: hexadecimal", "format: unknown")])
  internal func domains(_ replacement: (String, String)) {
    let source = kValidProfile
      .replacingOccurrences(of: replacement.0, with: replacement.1)
    #expect(throws: DSXCodeGenError.self) { try decode(source) }
  }

  @Test
  internal func valid() throws {
    let profile = try decode(kValidProfile)
    try validate(profile)

    #expect(profile.profile == "Test")
    #expect(profile.registers.count == 1)
  }

  @Test
  internal func aliases() throws {
    let source = kValidProfile
      .replacingOccurrences(of: "profile: Test", with: "profile: &name Test")
      .replacingOccurrences(of: "title: General", with: "title: *name")
    let profile = try decode(source)
    try validate(profile)
    #expect(profile.sets[0].title == "Test")
  }

  @Test
  internal func punctuation() throws {
    let source = kValidProfile
      .replacingOccurrences(of: "title: General }",
                            with: "title: 'General & Vector' } # x * y")
    let profile = try decode(source)
    try validate(profile)
    #expect(profile.sets[0].title == "General & Vector")
  }

  @Test
  internal func deterministic() throws {
    let profile = try decode(kValidProfile)
    try validate(profile)

    let first = generate(profile)
    let second = generate(profile)
    #expect(first.source == second.source)
    #expect(first.source.contains("architecture: StaticString = \"aarch64\""))
    #expect(first.source.contains("InlineArray<_, UInt64>"))
    #expect(first.source.contains("RegisterStorage("))
    #expect(first.source.contains("private static let kAliases"))
    #expect(first.source.contains("0x330500000000"))
  }

  @Test
  internal func platforms() throws {
    let profile = try decode(kConditionalProfile)
    try validate(profile)

    let source = generate(profile).source
    #expect(source.contains("#if os(anyAppleOS)"))
    #expect(source.contains("#elseif os(Linux)"))
    #expect(source.contains("kNames: StaticString = \"r0far\""))
    #expect(source.contains("kNames: StaticString = \"r0tpidr\""))
  }

  @Test
  internal func routing() throws {
    let definition = """
      - { pattern: qProcessInfo, leaf: info }
      - { pattern: "qProcessInfoPID:", leaf: process, exact: false }
      - { pattern: qSupported, leaf: supported, exact: false, scope: remote }
      - { pattern: M, leaf: memory, exact: false }
      - { pattern: "MultiMemRead:ranges:", leaf: ranges, exact: false }
      - { pattern: "qXfer:auxv:", leaf: transfer.auxiliary, exact: false }
      """
    let first = try packets(definition)
    let second = try packets(definition)
    #expect(first == second)
    #expect(first.contains("case info"))
    #expect(first.contains("case process"))
    #expect(first.contains("case ranges"))
    #expect(first.contains("case transfer(GDBTransferObject)"))
    #expect(first.contains("self = .transfer(.auxiliary)"))
    #expect(first.contains("private static let kTrie"))
    #expect(first.contains("case remote"))
  }

  @Test(arguments: ["feature: absent", "compatibility: absent"])
  internal func packet(_ value: String) {
    let definition = "- { pattern: qTest, leaf: test, \(value) }"
    #expect(throws: DSXCodeGenError.self) {
      try packets(definition)
    }
  }

  @Test
  internal func availability() {
    let definition = """
      - pattern: qTest
        leaf: test
        feature: stopthreads
        compatibility: lldb
      """
    #expect(throws: DSXCodeGenError.self) {
      try packets(definition)
    }
  }

  @Test
  internal func leaves() throws {
    let definitions = (0 ..< 256).map {
      "- { pattern: q\($0), leaf: test\($0) }"
    }
    let valid = try packets(definitions.prefix(255).joined(separator: "\n"))
    #expect(valid.contains("case 255: self = .test254"))
    #expect(throws: DSXCodeGenError.self) {
      try packets(definitions.joined(separator: "\n"))
    }
  }

  @Test
  internal func length() {
    let pattern = String(repeating: "q", count: 256)
    let definition = "- { pattern: \(pattern), leaf: test }"
    #expect(throws: DSXCodeGenError.self) {
      try packets(definition)
    }
  }

  @Test(arguments: kInvalidProfiles)
  internal func invalid(_ name: String, _ source: String) {
    #expect(throws: DSXCodeGenError.self) {
      let profile = try decode(source)
      try validate(profile)
    }
  }

  @Test
  internal func duplicates() {
    let register = kRegister
      .replacingOccurrences(of: "name: r0", with: "name: r1")
    let source = kValidProfile
      .replacingOccurrences(of: kRegisterEnd,
                            with: kRegisterEnd + "\n" + register)
    #expect(throws: DSXCodeGenError.self) {
      try validate(decode(source))
    }
  }

  @Test
  internal func overlap() {
    let register = kRegister
      .replacingOccurrences(of: "id: 0, name: r0", with: "id: 1, name: r1")
      .replacingOccurrences(of: "gdb: 0, lldb: 0", with: "gdb: 1, lldb: 1")
      .replacingOccurrences(of: "dwarf: 0, ehframe: 0",
                            with: "dwarf: 1, ehframe: 1")
    let source = kValidProfile
      .replacingOccurrences(of: kRegisterEnd,
                            with: kRegisterEnd + "\n" + register)
    #expect(throws: DSXCodeGenError.self) {
      try validate(decode(source))
    }
  }

  @Test(arguments: ["gdb", "lldb", "dwarf", "ehframe"])
  internal func numbering(_ domain: String) {
    var register = kRegister
      .replacingOccurrences(of: "id: 0, name: r0", with: "id: 1, name: r1")
      .replacingOccurrences(of: "role: result", with: "role: null")
      .replacingOccurrences(of: "gdb: 0, lldb: 0", with: "gdb: 1, lldb: 1")
      .replacingOccurrences(of: "dwarf: 0, ehframe: 0",
                            with: "dwarf: 1, ehframe: 1")
      .replacingOccurrences(of: "offset: 0", with: "offset: 8")
    register = register.replacingOccurrences(of: "\(domain): 1",
                                             with: "\(domain): 0")
    let source = kValidProfile
      .replacingOccurrences(of: kRegisterEnd,
                            with: kRegisterEnd + "\n" + register)
    #expect(throws: DSXCodeGenError.self) {
      try validate(decode(source))
    }
  }

  @Test
  internal func cycle() {
    let source = kValidProfile
      .replacingOccurrences(of: "includes: []",
                            with: "includes: [org.example.core]")
    #expect(throws: DSXCodeGenError.self) {
      try validate(decode(source))
    }
  }
}

private let kRegister =
    "  - { id: 0, name: r0, alternate: null, role: result, bits: 64, " +
    "offset: 0, set: gpr, encoding: unsigned, format: hexadecimal, " +
    "numbers: { gdb: 0, lldb: 0, dwarf: 0, ehframe: 0 }, relations: " +
    "{ containers: [], invalidates: [] }, feature: org.example.core, " +
    "type: uint64 }"
private let kRegisterEnd = "    type: uint64"
private let kConditionalProfile = """
profile: Conditional
architecture: arm64
layout: fixed
sets:
  - { id: 0, name: gpr, title: General }
  - { id: 1, name: exception, title: Exception, platforms: [apple] }
  - { id: 1, name: tls, title: Thread, platforms: [linux] }
features:
  - { id: 0, name: org.example.core, includes: [], types: [] }
registers:
  - id: 0
    name: r0
    alternate: null
    role: result
    bits: 64
    offset: 0
    set: gpr
    encoding: unsigned
    format: hexadecimal
    numbers: { gdb: 0, lldb: 0, dwarf: 0, ehframe: 0 }
    relations: { containers: [], invalidates: [] }
    feature: org.example.core
    type: uint64
  - id: 1
    name: far
    alternate: null
    role: null
    bits: 64
    offset: 8
    set: exception
    encoding: unsigned
    format: hexadecimal
    numbers: { gdb: null, lldb: 1, dwarf: null, ehframe: null }
    relations: { containers: [], invalidates: [] }
    feature: org.example.core
    type: uint64
    platforms: [apple]
  - id: 2
    name: tpidr
    alternate: null
    role: thread
    bits: 64
    offset: 8
    set: tls
    encoding: unsigned
    format: hexadecimal
    numbers: { gdb: 1, lldb: 1, dwarf: null, ehframe: null }
    relations: { containers: [], invalidates: [] }
    feature: org.example.core
    type: uint64
    platforms: [linux]
"""
private let kValidProfile = """
profile: Test
architecture: arm64
layout: fixed
sets:
  - { id: 0, name: gpr, title: General }
features:
  - { id: 0, name: org.example.core, includes: [], types: [] }
registers:
  - id: 0
    name: r0
    alternate: null
    role: result
    bits: 64
    offset: 0
    set: gpr
    encoding: unsigned
    format: hexadecimal
    numbers: { gdb: 0, lldb: 0, dwarf: 0, ehframe: 0 }
    relations: { containers: [], invalidates: [] }
    feature: org.example.core
    type: uint64
"""
