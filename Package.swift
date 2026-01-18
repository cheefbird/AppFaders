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
    // Pancake is an Xcode project, not SPM - will be addressed in Tasks 4-5
    // .package(url: "https://github.com/0bmxa/Pancake.git", branch: "master")
  ],
  targets: [
    .executableTarget(
      name: "AppFaders",
      dependencies: []
    ),
    .target(
      name: "AppFadersDriver",
      dependencies: [], // Pancake dependency deferred to Tasks 4-5
      linkerSettings: [
        .linkedFramework("CoreAudio"),
        .linkedFramework("AudioToolbox")
      ]
    ),
    .plugin(
      name: "BundleAssembler",
      capability: .buildTool()
    ),
    .testTarget(
      name: "AppFadersDriverTests",
      dependencies: ["AppFadersDriver"]
    )
  ]
)
