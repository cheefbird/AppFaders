import Dispatch
import Foundation

// AudioOrchestrator is @MainActor, so we use a Task running on the main actor
Task { @MainActor in
  print("AppFaders Host v0.2.0")

  let orchestrator = AudioOrchestrator()
  print("Orchestrator initialized. Starting...")

  // Handle SIGINT for clean shutdown
  let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  source.setEventHandler {
    print("\nReceived SIGINT. Shutting down...")
    orchestrator.stop()
    exit(0)
  }
  source.resume()

  // start loop (blocks until cancelled)
  await orchestrator.start()
}

// keep the main thread alive - allows the Task to run
dispatchMain()
