import CoreAudio
import Foundation
import os.log

// MARK: - Logging

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.driver", category: "VirtualStream")

// MARK: - VirtualStream

/// output stream for the virtual audio device
final class VirtualStream: @unchecked Sendable {
  static let shared = VirtualStream()

  let objectID = ObjectID.outputStream
  let ownerID = ObjectID.device

  // stream is output direction (0 = output, 1 = input)
  let direction: UInt32 = 0
  let startingChannel: UInt32 = 1
  let latencyFrames: UInt32 = 0

  private let lock = NSLock()

  // mutable state
  private var isActive: Bool = false
  private var sampleRate: Float64 = 48000.0

  /// supported sample rates
  let supportedSampleRates: [Float64] = [44100.0, 48000.0, 96000.0]

  private init() {
    os_log(.info, log: log, "VirtualStream created")
  }

  // MARK: - Format Helpers

  /// create AudioStreamBasicDescription for current sample rate
  func currentFormat() -> AudioStreamBasicDescription {
    lock.lock()
    let rate = sampleRate
    lock.unlock()
    return makeFormat(sampleRate: rate)
  }

  /// create format description for given sample rate
  private func makeFormat(sampleRate: Float64) -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
      mBytesPerPacket: 8, // 2 channels * 4 bytes
      mFramesPerPacket: 1,
      mBytesPerFrame: 8,
      mChannelsPerFrame: 2,
      mBitsPerChannel: 32,
      mReserved: 0
    )
  }

  /// get all available formats as AudioStreamRangedDescription array
  func availableFormats() -> [AudioStreamRangedDescription] {
    supportedSampleRates.map { rate in
      AudioStreamRangedDescription(
        mFormat: makeFormat(sampleRate: rate),
        mSampleRateRange: AudioValueRange(mMinimum: rate, mMaximum: rate)
      )
    }
  }

  // MARK: - Property Queries

  func hasProperty(address: AudioObjectPropertyAddress) -> Bool {
    switch address.mSelector {
    case kAudioObjectPropertyClass,
         kAudioObjectPropertyOwner,
         kAudioObjectPropertyOwnedObjects,
         kAudioStreamPropertyIsActive,
         kAudioStreamPropertyDirection,
         kAudioStreamPropertyTerminalType,
         kAudioStreamPropertyStartingChannel,
         kAudioStreamPropertyLatency,
         kAudioStreamPropertyVirtualFormat,
         kAudioStreamPropertyPhysicalFormat,
         kAudioStreamPropertyAvailableVirtualFormats,
         kAudioStreamPropertyAvailablePhysicalFormats:
      true
    default:
      false
    }
  }

  func isPropertySettable(address: AudioObjectPropertyAddress) -> Bool {
    switch address.mSelector {
    case kAudioStreamPropertyVirtualFormat,
         kAudioStreamPropertyPhysicalFormat:
      true
    default:
      false
    }
  }

  func getPropertyDataSize(address: AudioObjectPropertyAddress) -> UInt32? {
    switch address.mSelector {
    case kAudioObjectPropertyClass:
      UInt32(MemoryLayout<AudioClassID>.size)

    case kAudioObjectPropertyOwner,
         kAudioStreamPropertyStartingChannel,
         kAudioStreamPropertyLatency,
         kAudioStreamPropertyDirection,
         kAudioStreamPropertyTerminalType,
         kAudioStreamPropertyIsActive:
      UInt32(MemoryLayout<UInt32>.size)

    case kAudioObjectPropertyOwnedObjects:
      0 // stream owns nothing

    case kAudioStreamPropertyVirtualFormat,
         kAudioStreamPropertyPhysicalFormat:
      UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

    case kAudioStreamPropertyAvailableVirtualFormats,
         kAudioStreamPropertyAvailablePhysicalFormats:
      UInt32(MemoryLayout<AudioStreamRangedDescription>.size * supportedSampleRates.count)

    default:
      nil
    }
  }

  func getPropertyData(
    address: AudioObjectPropertyAddress,
    maxSize: UInt32
  ) -> (Data, UInt32)? {
    switch address.mSelector {
    case kAudioObjectPropertyClass:
      var classID = kAudioStreamClassID
      return (Data(bytes: &classID, count: MemoryLayout<AudioClassID>.size),
              UInt32(MemoryLayout<AudioClassID>.size))

    case kAudioObjectPropertyOwner:
      var owner = ownerID
      return (Data(bytes: &owner, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioObjectPropertyOwnedObjects:
      // stream owns nothing
      return (Data(), 0)

    case kAudioStreamPropertyIsActive:
      lock.lock()
      var active: UInt32 = isActive ? 1 : 0
      lock.unlock()
      return (Data(bytes: &active, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioStreamPropertyDirection:
      var dir = direction
      return (Data(bytes: &dir, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioStreamPropertyTerminalType:
      // kAudioStreamTerminalTypeSpeaker = 'spkr'
      var termType: UInt32 = 0x7370_6B72
      return (Data(bytes: &termType, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioStreamPropertyStartingChannel:
      var channel = startingChannel
      return (Data(bytes: &channel, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioStreamPropertyLatency:
      var latency = latencyFrames
      return (Data(bytes: &latency, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioStreamPropertyVirtualFormat,
         kAudioStreamPropertyPhysicalFormat:
      var format = currentFormat()
      return (Data(bytes: &format, count: MemoryLayout<AudioStreamBasicDescription>.size),
              UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

    case kAudioStreamPropertyAvailableVirtualFormats,
         kAudioStreamPropertyAvailablePhysicalFormats:
      var formats = availableFormats()
      let size = MemoryLayout<AudioStreamRangedDescription>.size * formats.count
      return (Data(bytes: &formats, count: size), UInt32(size))

    default:
      return nil
    }
  }

  // MARK: - Property Setting

  func setPropertyData(
    address: AudioObjectPropertyAddress,
    data: UnsafeRawPointer,
    size: UInt32
  ) -> OSStatus {
    switch address.mSelector {
    case kAudioStreamPropertyVirtualFormat,
         kAudioStreamPropertyPhysicalFormat:
      guard size >= UInt32(MemoryLayout<AudioStreamBasicDescription>.size) else {
        return kAudioHardwareBadPropertySizeError
      }

      let format = data.load(as: AudioStreamBasicDescription.self)

      // validate sample rate is supported
      guard supportedSampleRates.contains(format.mSampleRate) else {
        os_log(.error, log: log, "unsupported sample rate: %f", format.mSampleRate)
        return kAudioDeviceUnsupportedFormatError
      }

      // validate format matches our requirements
      guard format.mFormatID == kAudioFormatLinearPCM,
            format.mChannelsPerFrame == 2,
            format.mBitsPerChannel == 32
      else {
        os_log(.error, log: log, "unsupported format")
        return kAudioDeviceUnsupportedFormatError
      }

      lock.lock()
      sampleRate = format.mSampleRate
      lock.unlock()

      os_log(.info, log: log, "sample rate changed to %f", format.mSampleRate)
      return noErr

    default:
      return kAudioHardwareUnknownPropertyError
    }
  }

  // MARK: - IO State

  func setActive(_ active: Bool) {
    lock.lock()
    isActive = active
    lock.unlock()
    os_log(.info, log: log, "stream active: %{public}@", active ? "true" : "false")
  }

  func getIsActive() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return isActive
  }

  func getSampleRate() -> Float64 {
    lock.lock()
    defer { lock.unlock() }
    return sampleRate
  }
}

// MARK: - C Interface Exports

/// check if stream has property
@_cdecl("AppFadersDriver_Stream_HasProperty")
public func streamHasProperty(
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement
) -> Bool {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )
  return VirtualStream.shared.hasProperty(address: address)
}

/// check if stream property is settable
@_cdecl("AppFadersDriver_Stream_IsPropertySettable")
public func streamIsPropertySettable(
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement
) -> Bool {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )
  return VirtualStream.shared.isPropertySettable(address: address)
}

/// get stream property data size
@_cdecl("AppFadersDriver_Stream_GetPropertyDataSize")
public func streamGetPropertyDataSize(
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  outSize: UnsafeMutablePointer<UInt32>?
) -> OSStatus {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )

  guard let size = VirtualStream.shared.getPropertyDataSize(address: address) else {
    return kAudioHardwareUnknownPropertyError
  }

  outSize?.pointee = size
  return noErr
}

/// get stream property data
@_cdecl("AppFadersDriver_Stream_GetPropertyData")
public func streamGetPropertyData(
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  inDataSize: UInt32,
  outDataSize: UnsafeMutablePointer<UInt32>?,
  outData: UnsafeMutableRawPointer?
) -> OSStatus {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )

  guard
    let (data, actualSize) = VirtualStream.shared.getPropertyData(
      address: address,
      maxSize: inDataSize
    )
  else {
    return kAudioHardwareUnknownPropertyError
  }

  guard let outData, let outDataSize else {
    return kAudioHardwareIllegalOperationError
  }

  data.withUnsafeBytes { bytes in
    outData.copyMemory(from: bytes.baseAddress!, byteCount: Int(actualSize))
  }
  outDataSize.pointee = actualSize

  return noErr
}

/// set stream property data
@_cdecl("AppFadersDriver_Stream_SetPropertyData")
public func streamSetPropertyData(
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  dataSize: UInt32,
  data: UnsafeRawPointer?
) -> OSStatus {
  guard let data else {
    return kAudioHardwareIllegalOperationError
  }

  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )

  return VirtualStream.shared.setPropertyData(address: address, data: data, size: dataSize)
}

/// called when IO starts
@_cdecl("AppFadersDriver_StartIO")
public func driverStartIO(deviceID: AudioObjectID, clientID: UInt32) -> OSStatus {
  os_log(.info, log: log, "StartIO: device=%u client=%u", deviceID, clientID)
  VirtualStream.shared.setActive(true)
  VirtualDevice.shared.setRunning(true)

  let status = PassthroughEngine.shared.start()
  if status != noErr {
    os_log(.error, log: log, "StartIO: PassthroughEngine.start() failed: %d", status)
  }

  return noErr
}

/// called when IO stops
@_cdecl("AppFadersDriver_StopIO")
public func driverStopIO(deviceID: AudioObjectID, clientID: UInt32) -> OSStatus {
  os_log(.info, log: log, "StopIO: device=%u client=%u", deviceID, clientID)
  VirtualStream.shared.setActive(false)
  VirtualDevice.shared.setRunning(false)

  let status = PassthroughEngine.shared.stop()
  if status != noErr {
    os_log(.error, log: log, "StopIO: PassthroughEngine.stop() failed: %d", status)
  }

  return noErr
}
