// swift-tools-version:6.4
// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import PackageDescription

private let kFeatures: Array<SwiftSetting> = [
  .enableExperimentalFeature("Lifetimes"),
  .enableUpcomingFeature("InternalImportsByDefault"),
]

internal let package =
    Package(name: "DebugServerX", platforms: [.macOS(.v26)],
            products: [
              .executable(name: "dsx", targets: ["DebugServerX"]),
              .library(name: "DSX", type: .dynamic, targets: ["DSX"]),
            ],
            dependencies: [
              .package(url: "https://github.com/apple/swift-crypto",
                       from: "4.5.2"),
              .package(url: "https://github.com/jpsim/Yams", from: "6.1.0"),
            ],
            targets: [
              .executableTarget(name: "DebugServerX",
                                dependencies: ["DSX", "DSXArguments"],
                                linkerSettings: [
                                  .unsafeFlags([
                                    "-Xlinker",
                                    "/alternatename:_main=_DebugServerX_main",
                                  ], .when(platforms: [.windows])),
                                ]),
              .target(name: "DSXArguments", swiftSettings: kFeatures),
              .target(name: "DSX",
                      dependencies: [
                        "DSXShims",
                        .product(name: "Crypto", package: "swift-crypto",
                                 condition: .when(platforms: [.android])),
                      ],
                      swiftSettings: kFeatures,
                      linkerSettings: [
                        .linkedLibrary("bcrypt", .when(platforms: [.windows])),
                        .linkedLibrary("crypto", .when(platforms: [.linux])),
                        .linkedLibrary("md",
                                       .when(platforms: [.custom("freebsd")])),
                        .linkedLibrary("Pathcch", .when(platforms: [.windows])),
                        .linkedLibrary("ntdll", .when(platforms: [.windows])),
                        .linkedLibrary("Ws2_32", .when(platforms: [.windows])),
                      ],
                      plugins: [.plugin(name: "DefinitionsPlugin")]),
              .target(name: "DSXShims", path: "Sources/DSXShims",
                      publicHeadersPath: "include"),
              .executableTarget(name: "DSXCodeGen",
                                dependencies: [
                                  .product(name: "Yams", package: "Yams"),
                                ]),
              .plugin(name: "DefinitionsPlugin", capability: .buildTool(),
                      dependencies: ["DSXCodeGen"]),
              .testTarget(name: "DebugServerXTests",
                          dependencies: ["DebugServerX"],
                          swiftSettings: kFeatures),
              .testTarget(name: "DSXTests", dependencies: ["DSX"],
                          swiftSettings: kFeatures),
              .testTarget(name: "DSXCodeGenTests", dependencies: ["DSXCodeGen"],
                          swiftSettings: kFeatures),
            ])
