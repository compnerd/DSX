// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import struct Foundation.Data
import class Foundation.FileHandle
import struct Foundation.URL

#if os(Windows)
internal import CRT
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

@main
internal enum DSXCodeGen {
  internal static func main() {
    do {
      try run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}

internal func run(_ arguments: Array<String>) throws(DSXCodeGenError) {
  var index = 0
  var profiles = Array<(String, String)>()
  var destination: String?
  var packet: (String, String)?
  while index < arguments.count {
    switch arguments[index] {
    case "--profile":
      guard index + 2 < arguments.count else {
        throw .argument("--profile requires an input and output")
      }
      profiles.append((arguments[index + 1], arguments[index + 2]))
      index += 3
    case "--registry":
      guard index + 1 < arguments.count else {
        throw .argument("--registry requires an output")
      }
      destination = arguments[index + 1]
      index += 2
    case "--packets":
      guard index + 2 < arguments.count else {
        throw .argument("--packets requires an input and output")
      }
      packet = (arguments[index + 1], arguments[index + 2])
      index += 3
    default:
      throw .argument("unknown argument '\(arguments[index])'")
    }
  }
  guard !profiles.isEmpty else {
    throw .argument("at least one profile is required")
  }
  guard let destination else {
    throw .argument("--registry is required")
  }

  var generated = Array<GeneratedProfile>()
  for (input, output) in profiles {
    let source = try read(input)
    let definition = try decode(source)
    try validate(definition)
    let profile = generate(definition)
    try write(profile.source, to: output)
    generated.append(profile)
  }
  try write(registry(generated), to: destination)
  if let packet {
    let source = try read(packet.0)
    try write(packets(source), to: packet.1)
  }
}

private func read(_ path: String) throws(DSXCodeGenError) -> String {
  do {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return String(decoding: data, as: UTF8.self)
  } catch {
    throw .input(path)
  }
}

private func write(_ source: String, to path: String) throws(DSXCodeGenError) {
  do {
    try Data(source.utf8).write(to: URL(fileURLWithPath: path),
                                options: .atomic)
  } catch {
    throw .output(path)
  }
}
