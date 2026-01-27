import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.helper", category: "Main")
private let machServiceName = "com.fbreidenbach.appfaders.helper"

/// Delegate for accepting XPC connections
final class ListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    os_log(.info, log: log, "Accepting new XPC connection")

    // Configure the connection's exported interface
    // Both host and driver use AppFadersHostProtocol for now
    // (driver only calls the read methods)
    newConnection.exportedInterface = NSXPCInterface(with: AppFadersHostProtocol.self)
    newConnection.exportedObject = HelperService.shared

    // Handle connection lifecycle
    newConnection.invalidationHandler = {
      os_log(.info, log: log, "XPC connection invalidated")
    }
    newConnection.interruptionHandler = {
      os_log(.info, log: log, "XPC connection interrupted")
    }

    newConnection.resume()
    return true
  }
}

// MARK: - Entry Point

os_log(.info, log: log, "AppFadersHelper starting with service: %{public}@", machServiceName)

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()

os_log(.info, log: log, "XPC listener started, entering run loop")
RunLoop.main.run()
