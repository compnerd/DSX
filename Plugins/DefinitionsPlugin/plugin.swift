// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import PackagePlugin

@main
internal struct DefinitionsPlugin: BuildToolPlugin {
  internal func createBuildCommands(context: PluginContext,
                                    target: Target) async throws
      -> Array<Command> {
    let tool = try context.tool(named: "DSXCodeGen")
    let definitions = context.package.directoryURL
      .appending(path: "Definitions")
      .appending(path: "Registers")
    let arm32 = definitions.appending(path: "ARM.yaml")
    let arm64 = definitions.appending(path: "ARM64.yaml")
    let i386 = definitions.appending(path: "I386.yaml")
    let amd64 = definitions.appending(path: "X86_64.yaml")
    let arm = context.pluginWorkDirectoryURL
      .appending(path: "ARMRegisters.swift")
    let aarch64 = context.pluginWorkDirectoryURL
      .appending(path: "ARM64Registers.swift")
    let x86 = context.pluginWorkDirectoryURL
      .appending(path: "I386Registers.swift")
    let x64 = context.pluginWorkDirectoryURL
      .appending(path: "X86_64Registers.swift")
    let registry = context.pluginWorkDirectoryURL
      .appending(path: "NativeRegisterProfile.swift")
    let packets = context.package.directoryURL
      .appending(path: "Definitions")
      .appending(path: "Packets.yaml")
    let classifier = context.pluginWorkDirectoryURL
      .appending(path: "GDBPacketRoutes.swift")
    let outputs = [
      arm, aarch64, x86, x64, registry, classifier,
    ]

    return [
      .buildCommand(displayName: "Generate definitions", executable: tool.url,
                    arguments: [
                      "--profile", arm32.path(), arm.path(),
                      "--profile", arm64.path(), aarch64.path(),
                      "--profile", i386.path(), x86.path(),
                      "--profile", amd64.path(), x64.path(),
                      "--registry", registry.path(),
                      "--packets", packets.path(), classifier.path(),
                    ], inputFiles: [arm32, arm64, i386, amd64, packets],
                    outputFiles: outputs),
    ]
  }
}
