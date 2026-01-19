// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AppFaders",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .executable(name: "AppFaders", targets: ["AppFaders"]),
    .library(name: "AppFadersDriver", type: .dynamic, targets: ["AppFadersDriver"]),
    .plugin(name: "BundleAssembler", targets: ["BundleAssembler"])
  ],
  dependencies: [
    // Pancake is an Xcode project, not SPM - see docs/pancake-compatibility.md
    // .package(url: "https://github.com/0bmxa/Pancake.git", branch: "master")
    .package(url: "https://github.com/rnine/SimplyCoreAudio.git", from: "4.1.0")
  ],
  targets: [
    .executableTarget(
      name: "AppFaders",
      dependencies: [
        .product(name: "SimplyCoreAudio", package: "SimplyCoreAudio")
      ]
    ),
    // C interface layer for HAL AudioServerPlugIn
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
        // Build as MH_BUNDLE instead of MH_DYLIB for CFPlugIn compatibility
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
