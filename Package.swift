// swift-tools-version:6.4

import PackageDescription

let features: Array<SwiftSetting> = [
  .enableExperimentalFeature("Lifetimes"),
  .enableUpcomingFeature("InternalImportsByDefault"),
]

let package =
    Package(name: "DebugServerX",
            platforms: [
              .macOS(.v26),
            ],
            products: [
              .executable(name: "dsx", targets: ["DebugServerX"]),
              .library(name: "DSX", type: .dynamic, targets: ["DSX"]),
            ],
            dependencies: [
              .package(url: "https://github.com/jpsim/Yams", from: "6.1.0"),
            ],
            targets: [
              .executableTarget(name: "DebugServerX",
                                dependencies: [
                                  "DSX",
                                  "DSXArguments",
                                ],
                                linkerSettings: [
                                  .unsafeFlags([
                                    "-Xlinker",
                                    "/alternatename:_main=_DebugServerX_main",
                                  ], .when(platforms: [.windows])),
                                ]),
              .target(name: "DSXArguments", swiftSettings: features),
              .target(name: "DSX",
                      dependencies: [
                        "DSXShims",
                      ],
                      swiftSettings: features,
                      linkerSettings: [
                        .linkedLibrary("Pathcch", .when(platforms: [.windows])),
                        .linkedLibrary("ntdll", .when(platforms: [.windows])),
                        .linkedLibrary("Ws2_32", .when(platforms: [.windows])),
                      ],
                      plugins: [
                        .plugin(name: "DefinitionsPlugin"),
                      ]),
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
                          swiftSettings: features),
              .testTarget(name: "DSXTests", dependencies: ["DSX"],
                          swiftSettings: features),
              .testTarget(name: "DSXCodeGenTests", dependencies: ["DSXCodeGen"],
                          swiftSettings: features),
            ])
