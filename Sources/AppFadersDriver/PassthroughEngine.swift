import AudioToolbox
import CoreAudio
import Foundation
import os.log
import Synchronization

// MARK: - Logging

private let log = OSLog(
  subsystem: "com.fbreidenbach.appfaders.driver",
  category: "PassthroughEngine"
)

// MARK: - Missing CoreAudio Constants

// HAL plug-in IO operation type - not bridged to Swift
private let kAudioServerPlugInIOOperationWriteMix: UInt32 = 2

// MARK: - Ring Buffer

/// lock-free single-producer single-consumer ring buffer for audio samples
/// pre-allocated to avoid runtime allocations
final class AudioRingBuffer: @unchecked Sendable {
  // buffer size in frames - must be power of 2 for efficient modulo
  // 8192 frames at 48kHz = ~170ms of buffer
  private let capacity: Int = 8192
  private let channelCount: Int = 2

  // pre-allocated buffer storage
  private var buffer: UnsafeMutablePointer<Float>
  private let bufferSampleCount: Int

  // atomic indices for lock-free operation
  private let writeIndex: Atomic<Int>
  private let readIndex: Atomic<Int>

  init() {
    bufferSampleCount = capacity * channelCount
    buffer = .allocate(capacity: bufferSampleCount)
    buffer.initialize(repeating: 0.0, count: bufferSampleCount)

    writeIndex = Atomic(0)
    readIndex = Atomic(0)
  }

  deinit {
    buffer.deinitialize(count: bufferSampleCount)
    buffer.deallocate()
  }

  /// write frames to buffer (called from virtual device IO thread)
  /// returns number of frames actually written
  func write(frames: UnsafePointer<Float>, frameCount: Int) -> Int {
    let samplesToWrite = frameCount * channelCount
    let currentWrite = writeIndex.load(ordering: .relaxed)
    let currentRead = readIndex.load(ordering: .acquiring)

    // calculate available space
    let used = (currentWrite - currentRead + bufferSampleCount) % bufferSampleCount
    let available = bufferSampleCount - used - 1

    let actualSamples = min(samplesToWrite, available)
    let actualFrames = actualSamples / channelCount

    // copy samples to buffer
    for i in 0 ..< actualSamples {
      let idx = (currentWrite + i) % bufferSampleCount
      buffer[idx] = frames[i]
    }

    // update write index atomically
    writeIndex.store((currentWrite + actualSamples) % bufferSampleCount, ordering: .releasing)

    return actualFrames
  }

  /// read frames from buffer (called from output device IO thread)
  /// returns number of frames actually read, fills remainder with silence
  func read(into frames: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
    let samplesToRead = frameCount * channelCount
    let currentWrite = writeIndex.load(ordering: .acquiring)
    let currentRead = readIndex.load(ordering: .relaxed)

    // calculate available data
    let available = (currentWrite - currentRead + bufferSampleCount) % bufferSampleCount
    let actualSamples = min(samplesToRead, available)
    let actualFrames = actualSamples / channelCount

    // copy samples from buffer
    for i in 0 ..< actualSamples {
      let idx = (currentRead + i) % bufferSampleCount
      frames[i] = buffer[idx]
    }

    // fill remainder with silence
    if actualSamples < samplesToRead {
      for i in actualSamples ..< samplesToRead {
        frames[i] = 0.0
      }
    }

    // update read index atomically
    readIndex.store((currentRead + actualSamples) % bufferSampleCount, ordering: .releasing)

    return actualFrames
  }

  /// reset buffer state (call only when IO is stopped)
  func reset() {
    writeIndex.store(0, ordering: .relaxed)
    readIndex.store(0, ordering: .relaxed)
    // zero out buffer
    for i in 0 ..< bufferSampleCount {
      buffer[i] = 0.0
    }
  }
}

// MARK: - PassthroughEngine

/// routes audio from virtual device to default physical output
final class PassthroughEngine: @unchecked Sendable {
  static let shared = PassthroughEngine()

  private var outputDeviceID: AudioDeviceID = kAudioObjectUnknown
  private var ioProcID: AudioDeviceIOProcID?
  private var isRunning = false

  private let ringBuffer = AudioRingBuffer()
  private let lock = NSLock()

  private init() {
    os_log(.info, log: log, "PassthroughEngine created")
  }

  // MARK: - Lifecycle

  /// start audio passthrough - finds default output and sets up IOProc
  func start() -> OSStatus {
    lock.lock()
    defer { lock.unlock() }

    guard !isRunning else {
      os_log(.info, log: log, "start called but already running")
      return noErr
    }

    // find default output device
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var deviceID: AudioDeviceID = kAudioObjectUnknown
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

    var status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0, nil,
      &propertySize,
      &deviceID
    )

    if status != noErr || deviceID == kAudioObjectUnknown {
      os_log(.error, log: log, "failed to get default output device: %d", status)
      return status != noErr ? status : kAudioHardwareBadDeviceError
    }

    outputDeviceID = deviceID
    os_log(.info, log: log, "found default output device: %u", deviceID)

    // reset ring buffer before starting
    ringBuffer.reset()

    // create IOProc on output device
    var procID: AudioDeviceIOProcID?
    status = AudioDeviceCreateIOProcID(
      deviceID,
      outputIOProc,
      Unmanaged.passUnretained(self).toOpaque(),
      &procID
    )

    if status != noErr {
      os_log(.error, log: log, "failed to create IOProc: %d", status)
      return status
    }

    ioProcID = procID
    os_log(.debug, log: log, "created IOProc")

    // start the IOProc
    status = AudioDeviceStart(deviceID, procID)
    if status != noErr {
      os_log(.error, log: log, "failed to start IOProc: %d", status)
      AudioDeviceDestroyIOProcID(deviceID, procID!)
      ioProcID = nil
      return status
    }

    isRunning = true
    os_log(.info, log: log, "passthrough started")

    return noErr
  }

  /// stop audio passthrough
  func stop() -> OSStatus {
    lock.lock()
    defer { lock.unlock() }

    guard isRunning else {
      os_log(.info, log: log, "stop called but not running")
      return noErr
    }

    guard let procID = ioProcID, outputDeviceID != kAudioObjectUnknown else {
      os_log(.error, log: log, "stop called but no valid IOProc")
      isRunning = false
      return noErr
    }

    // stop the IOProc
    var status = AudioDeviceStop(outputDeviceID, procID)
    if status != noErr {
      os_log(.error, log: log, "failed to stop IOProc: %d", status)
    }

    // destroy the IOProc
    status = AudioDeviceDestroyIOProcID(outputDeviceID, procID)
    if status != noErr {
      os_log(.error, log: log, "failed to destroy IOProc: %d", status)
    }

    ioProcID = nil
    outputDeviceID = kAudioObjectUnknown
    isRunning = false

    os_log(.info, log: log, "passthrough stopped")

    return noErr
  }

  // MARK: - Audio Processing

  /// called from virtual device DoIOOperation - writes audio to ring buffer
  /// this must be real-time safe
  func processBuffer(_ buffer: UnsafeRawPointer, frameCount: UInt32) {
    // convert to float pointer (we use 32-bit float, stereo)
    let floatBuffer = buffer.assumingMemoryBound(to: Float.self)
    _ = ringBuffer.write(frames: floatBuffer, frameCount: Int(frameCount))
  }

  /// returns true if passthrough is active
  func getIsRunning() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return isRunning
  }

  /// read audio from ring buffer into output buffer (called from output IOProc)
  /// this must be real-time safe
  func readIntoOutputBuffer(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
    ringBuffer.read(into: buffer, frameCount: frameCount)
  }
}

// MARK: - Output IOProc

/// IOProc callback for the physical output device
/// this runs on the audio device's real-time thread
private func outputIOProc(
  _ deviceID: AudioDeviceID,
  _ now: UnsafePointer<AudioTimeStamp>,
  _ inputData: UnsafePointer<AudioBufferList>,
  _ inputTime: UnsafePointer<AudioTimeStamp>,
  _ outputData: UnsafeMutablePointer<AudioBufferList>,
  _ outputTime: UnsafePointer<AudioTimeStamp>,
  _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let clientData else { return noErr }

  let engine = Unmanaged<PassthroughEngine>.fromOpaque(clientData).takeUnretainedValue()

  // get the output buffer
  let bufferList = outputData.pointee
  guard bufferList.mNumberBuffers > 0 else { return noErr }

  // access first buffer
  let buffer = UnsafeMutableAudioBufferListPointer(outputData)[0]
  guard let data = buffer.mData else { return noErr }

  let frameCount = buffer.mDataByteSize / 8 // 2 channels * 4 bytes per sample
  let floatBuffer = data.assumingMemoryBound(to: Float.self)

  // read from ring buffer into output
  _ = engine.readIntoOutputBuffer(floatBuffer, frameCount: Int(frameCount))

  return noErr
}

// MARK: - C Interface Export

/// called from PlugInInterface.c DoIOOperation
@_cdecl("AppFadersDriver_DoIOOperation")
public func driverDoIOOperation(
  deviceID: AudioObjectID,
  streamID: AudioObjectID,
  clientID: UInt32,
  operationID: UInt32,
  ioBufferFrameSize: UInt32,
  ioMainBuffer: UnsafeMutableRawPointer?,
  ioSecondaryBuffer: UnsafeMutableRawPointer?
) -> OSStatus {
  // we only handle WriteMix operation (apps writing audio to our device)
  guard operationID == kAudioServerPlugInIOOperationWriteMix else {
    return noErr
  }

  guard let buffer = ioMainBuffer else {
    return noErr
  }

  PassthroughEngine.shared.processBuffer(buffer, frameCount: ioBufferFrameSize)

  return noErr
}
