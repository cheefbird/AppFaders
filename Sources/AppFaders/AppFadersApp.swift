import AppKit

@main
struct AppFadersApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // run() blocks until app terminates, keeping delegate alive
    app.run()
  }
}
