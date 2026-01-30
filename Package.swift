// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AppFaders",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .executable(name: "AppFaders", targets: ["AppFaders"]),
    .executable(name: "AppFadersHelper", targets: ["AppFadersHelper"]),
    .library(name: "AppFadersDriver", type: .dynamic, targets: ["AppFadersDriver"]),
    .library(name: "AppFadersCore", targets: ["AppFadersCore"]),
    .plugin(name: "BundleAssembler", targets: ["BundleAssembler"])
  ],
  dependencies: [
    .package(url: "https://github.com/sbooth/CAAudioHardware", from: "0.7.1")
  ],
  targets: [
    .target(
      name: "AppFadersCore",
      dependencies: []
    ),
    .executableTarget(
      name: "AppFaders",
      dependencies: [
        .product(name: "CAAudioHardware", package: "CAAudioHardware")
      ]
    ),
    .executableTarget(
      name: "AppFadersHelper",
      dependencies: []
    ),
    .target(
      name: "AppFadersDriverBridge",
      dependencies: [],
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("include")
      ],
      linkerSettings: [
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreFoundation")
      ]
    ),
    .target(
      name: "AppFadersDriver",
      dependencies: ["AppFadersDriverBridge"],
      linkerSettings: [
        .linkedFramework("CoreAudio"),
        .linkedFramework("AudioToolbox"),
        .unsafeFlags(["-Xlinker", "-bundle"])
      ],
      plugins: [
        .plugin(name: "BundleAssembler")
      ]
    ),
    .plugin(
      name: "BundleAssembler",
      capability: .buildTool()
    ),
    .testTarget(
      name: "AppFadersDriverTests",
      dependencies: ["AppFadersDriver"]
    ),
    .testTarget(
      name: "AppFadersTests",
      dependencies: ["AppFaders"]
    )
  ]
)
