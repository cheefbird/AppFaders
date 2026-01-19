import Foundation
import PackagePlugin

/// Build tool plugin that assembles the AppFadersDriver.driver bundle structure
/// Creates Contents/, Contents/MacOS/, Contents/Resources/ and copies Info.plist
/// The actual binary is copied by the install script after build completes
@main
struct BundleAssembler: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    // only run for the AppFadersDriver target
    guard target.name == "AppFadersDriver" else {
      return []
    }

    // bundle goes in plugin work directory
    let bundleDir = context.pluginWorkDirectoryURL
      .appendingPathComponent("AppFadersDriver.driver")
    let contentsDir = bundleDir.appendingPathComponent("Contents")
    let macOSDir = contentsDir.appendingPathComponent("MacOS")
    let resourcesDir = contentsDir.appendingPathComponent("Resources")

    // create directory structure
    let fm = FileManager.default
    try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

    // find Info.plist in package root
    let packageDir = context.package.directoryURL
    let infoPlistSource = packageDir.appendingPathComponent("Resources/Info.plist")
    let infoPlistDest = contentsDir.appendingPathComponent("Info.plist")

    // copy Info.plist (remove existing first if needed)
    if fm.fileExists(atPath: infoPlistDest.path) {
      try fm.removeItem(at: infoPlistDest)
    }
    try fm.copyItem(at: infoPlistSource, to: infoPlistDest)

    // write a marker file so install script knows where bundle is
    let markerFile = bundleDir.appendingPathComponent(".bundle-ready")
    try "Bundle structure created by BundleAssembler plugin".write(
      to: markerFile,
      atomically: true,
      encoding: .utf8
    )

    // no build commands needed - we did the work directly
    // the install script will copy the binary after build
    return []
  }
}
