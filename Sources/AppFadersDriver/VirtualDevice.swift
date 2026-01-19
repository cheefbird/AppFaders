// VirtualDevice.swift
// AudioObject implementation for "AppFaders Virtual Device"
//
// implements property handlers for the virtual audio device that appears
// in System Settings. coreaudiod queries these properties to display
// device info and route audio.

import CoreAudio
import Foundation
import os.log

// MARK: - Object IDs

// static object IDs for our audio object hierarchy
// these must be unique within the driver and stable across sessions
public enum ObjectID {
  static let plugIn: AudioObjectID = 1
  static let device: AudioObjectID = 2
  static let outputStream: AudioObjectID = 3
  // room for more: inputStream = 4, volumeControl = 5, etc
}

// MARK: - Missing CoreAudio Constants

// these HAL-specific constants aren't bridged to Swift
private let kAudioPlugInPropertyResourceBundle = AudioObjectPropertySelector(
  fourCharCode("rsrc"))
private let kAudioDevicePropertyZeroTimeStampPeriod = AudioObjectPropertySelector(
  fourCharCode("ring"))
private let kAudioObjectPropertyCustomPropertyInfoList = AudioObjectPropertySelector(
  fourCharCode("cust"))
private let kAudioDevicePropertyControlList = AudioObjectPropertySelector(
  fourCharCode("ctrl"))
private let kAudioClockDevicePropertyClockDomain = AudioObjectPropertySelector(
  fourCharCode("clk#"))

private func fourCharCode(_ string: String) -> UInt32 {
  var result: UInt32 = 0
  for char in string.utf8.prefix(4) {
    result = (result << 8) | UInt32(char)
  }
  return result
}

private func fourCharCodeToString(_ code: UInt32) -> String {
  let chars: [Character] = [
    Character(UnicodeScalar((code >> 24) & 0xFF)!),
    Character(UnicodeScalar((code >> 16) & 0xFF)!),
    Character(UnicodeScalar((code >> 8) & 0xFF)!),
    Character(UnicodeScalar(code & 0xFF)!)
  ]
  return String(chars)
}

// MARK: - Logging

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.driver", category: "VirtualDevice")

// MARK: - VirtualDevice

/// the virtual audio device that apps can select as output
final class VirtualDevice: @unchecked Sendable {
  static let shared = VirtualDevice()

  let objectID = ObjectID.device
  let name = "AppFaders" as CFString
  let manufacturer = "AppFaders" as CFString
  let uid = "com.fbreidenbach.appfaders.virtualdevice" as CFString
  let modelUID = "com.fbreidenbach.appfaders.model" as CFString
  let resourceBundle = "" as CFString // no resource bundle

  private let lock = NSLock()

  // MARK: - CFString Helper

  /// returns CFStringRef as pointer data - CoreAudio expects the pointer value, not serialized
  /// bytes
  private func cfStringPropertyData(_ string: CFString) -> (Data, UInt32) {
    var ptr = Unmanaged.passUnretained(string).toOpaque()
    return (Data(bytes: &ptr, count: MemoryLayout<UnsafeRawPointer>.size),
            UInt32(MemoryLayout<UnsafeRawPointer>.size))
  }

  // mutable state
  private var isRunning: Bool = false
  private var sampleRate: Float64 = 48000.0

  private init() {
    os_log(.info, log: log, "VirtualDevice created")
  }

  // MARK: - Property Queries

  /// check if object supports a property
  func hasProperty(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> Bool {
    // handle plug-in level properties
    if objectID == ObjectID.plugIn {
      return hasPlugInProperty(address: address)
    }

    // handle device level properties
    if objectID == ObjectID.device {
      return hasDeviceProperty(address: address)
    }

    // delegate stream properties to VirtualStream
    if objectID == ObjectID.outputStream {
      return VirtualStream.shared.hasProperty(address: address)
    }

    return false
  }

  /// check if property can be changed
  func isPropertySettable(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> Bool {
    // device sample rate is settable
    if objectID == ObjectID.device,
       address.mSelector == kAudioDevicePropertyNominalSampleRate
    {
      return true
    }

    // custom IPC property for setting app volumes
    if objectID == ObjectID.device,
       address.mSelector == AppFadersProperty.setVolume
    {
      return true
    }

    // delegate stream properties to VirtualStream
    if objectID == ObjectID.outputStream {
      return VirtualStream.shared.isPropertySettable(address: address)
    }

    return false
  }

  /// get size in bytes needed for property data
  func getPropertyDataSize(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    qualifierSize: UInt32,
    qualifierData: UnsafeRawPointer?
  ) -> UInt32? {
    let result: UInt32? = if objectID == ObjectID.plugIn {
      getPlugInPropertyDataSize(address: address)
    } else if objectID == ObjectID.device {
      getDevicePropertyDataSize(address: address)
    } else if objectID == ObjectID.outputStream {
      VirtualStream.shared.getPropertyDataSize(address: address)
    } else {
      nil
    }

    if result == nil {
      os_log(
        .error,
        log: log,
        "getPropertyDataSize: unknown - objectID=%u selector=%{public}@ (0x%x) scope=0x%x element=%u",
        objectID,
        fourCharCodeToString(address.mSelector),
        address.mSelector,
        address.mScope,
        address.mElement
      )
    }

    return result
  }

  /// get property value - returns (data, actualSize) or nil if unknown
  func getPropertyData(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    maxSize: UInt32,
    qualifierSize: UInt32,
    qualifierData: UnsafeRawPointer?
  ) -> (Data, UInt32)? {
    if objectID == ObjectID.plugIn {
      return getPlugInPropertyData(address: address, maxSize: maxSize)
    }

    if objectID == ObjectID.device {
      return getDevicePropertyData(address: address, maxSize: maxSize, qualifierSize: qualifierSize, qualifierData: qualifierData)
    }

    if objectID == ObjectID.outputStream {
      return VirtualStream.shared.getPropertyData(address: address, maxSize: maxSize)
    }

    return nil
  }

  // MARK: - Plug-In Properties

  private func hasPlugInProperty(address: AudioObjectPropertyAddress) -> Bool {
    let has = switch address.mSelector {
    case kAudioObjectPropertyClass,
         kAudioObjectPropertyBaseClass,
         kAudioObjectPropertyOwner,
         kAudioObjectPropertyManufacturer,
         kAudioObjectPropertyOwnedObjects,
         kAudioObjectPropertyCustomPropertyInfoList,
         kAudioPlugInPropertyBoxList,
         kAudioPlugInPropertyTranslateUIDToBox,
         kAudioPlugInPropertyDeviceList,
         kAudioPlugInPropertyTranslateUIDToDevice,
         kAudioPlugInPropertyResourceBundle,
         kAudioClockDevicePropertyClockDomain:
      true
    default:
      false
    }
    if !has {
      os_log(.error, log: log, "hasPlugInProperty: unknown selector %{public}@ (0x%x)",
             fourCharCodeToString(address.mSelector), address.mSelector)
    }
    return has
  }

  private func getPlugInPropertyDataSize(address: AudioObjectPropertyAddress) -> UInt32? {
    switch address.mSelector {
    case kAudioObjectPropertyClass,
         kAudioObjectPropertyBaseClass:
      return UInt32(MemoryLayout<AudioClassID>.size)

    case kAudioObjectPropertyOwner:
      return UInt32(MemoryLayout<AudioObjectID>.size)

    case kAudioObjectPropertyManufacturer:
      return UInt32(MemoryLayout<CFString>.size)

    case kAudioObjectPropertyOwnedObjects,
         kAudioPlugInPropertyDeviceList:
      return UInt32(MemoryLayout<AudioObjectID>.size) // one device

    case kAudioObjectPropertyCustomPropertyInfoList,
         kAudioPlugInPropertyBoxList:
      return 0 // empty lists

    case kAudioPlugInPropertyTranslateUIDToBox:
      return UInt32(MemoryLayout<AudioObjectID>.size)

    case kAudioPlugInPropertyTranslateUIDToDevice:
      return UInt32(MemoryLayout<AudioObjectID>.size)

    case kAudioPlugInPropertyResourceBundle:
      return UInt32(MemoryLayout<CFString>.size)

    case kAudioClockDevicePropertyClockDomain:
      return UInt32(MemoryLayout<UInt32>.size)

    default:
      return nil
    }
  }



  private func getPlugInPropertyData(
    address: AudioObjectPropertyAddress,
    maxSize: UInt32
  ) -> (Data, UInt32)? {
    switch address.mSelector {
    case kAudioObjectPropertyClass:
      var classID = kAudioPlugInClassID
      return (Data(bytes: &classID, count: MemoryLayout<AudioClassID>.size),
              UInt32(MemoryLayout<AudioClassID>.size))

    case kAudioObjectPropertyBaseClass:
      var classID = kAudioObjectClassID
      return (Data(bytes: &classID, count: MemoryLayout<AudioClassID>.size),
              UInt32(MemoryLayout<AudioClassID>.size))

    case kAudioObjectPropertyOwner:
      var owner = kAudioObjectSystemObject
      return (Data(bytes: &owner, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioObjectPropertyManufacturer:
      return cfStringPropertyData(manufacturer)

    case kAudioObjectPropertyOwnedObjects,
         kAudioPlugInPropertyDeviceList:
      var deviceID = ObjectID.device
      return (Data(bytes: &deviceID, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioObjectPropertyCustomPropertyInfoList,
         kAudioPlugInPropertyBoxList:
      // empty lists
      return (Data(), 0)

    case kAudioPlugInPropertyTranslateUIDToBox:
      // no boxes - return unknown object
      var boxID = kAudioObjectUnknown
      return (Data(bytes: &boxID, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioPlugInPropertyTranslateUIDToDevice:
      // qualifier contains UID to translate - for now just return our device
      var deviceID = ObjectID.device
      return (Data(bytes: &deviceID, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioPlugInPropertyResourceBundle:
      return cfStringPropertyData(resourceBundle)

    case kAudioClockDevicePropertyClockDomain:
      var domain: UInt32 = 0
      return (Data(bytes: &domain, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    default:
      return nil
    }
  }

  // MARK: - Device Properties

  private func hasDeviceProperty(address: AudioObjectPropertyAddress) -> Bool {
    let has = switch address.mSelector {
    case kAudioObjectPropertyClass,
         kAudioObjectPropertyBaseClass,
         kAudioObjectPropertyOwner,
         kAudioObjectPropertyName,
         kAudioObjectPropertyManufacturer,
         kAudioObjectPropertyOwnedObjects,
         kAudioObjectPropertyCustomPropertyInfoList,
         kAudioDevicePropertyDeviceUID,
         kAudioDevicePropertyModelUID,
         kAudioDevicePropertyTransportType,
         kAudioDevicePropertyDeviceIsRunning,
         kAudioDevicePropertyDeviceCanBeDefaultDevice,
         kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
         kAudioDevicePropertyStreams,
         kAudioDevicePropertyControlList,
         kAudioDevicePropertyNominalSampleRate,
         kAudioDevicePropertyAvailableNominalSampleRates,
         kAudioDevicePropertyLatency,
         kAudioDevicePropertySafetyOffset,
         kAudioDevicePropertyZeroTimeStampPeriod,
         kAudioDevicePropertyClockDomain,
         kAudioDevicePropertyIsHidden,
         kAudioDevicePropertyPreferredChannelsForStereo,
         AppFadersProperty.setVolume,
         AppFadersProperty.getVolume:
      true
    default:
      false
    }
    if !has {
      os_log(.debug, log: log, "hasDeviceProperty: unknown selector %{public}@ (0x%x)",
             fourCharCodeToString(address.mSelector), address.mSelector)
    }
    return has
  }

  private func getDevicePropertyDataSize(address: AudioObjectPropertyAddress) -> UInt32? {
    switch address.mSelector {
    case kAudioObjectPropertyClass,
         kAudioObjectPropertyBaseClass,
         kAudioDevicePropertyTransportType,
         kAudioDevicePropertyClockDomain:
      return UInt32(MemoryLayout<AudioClassID>.size)

    case kAudioObjectPropertyOwner,
         kAudioDevicePropertyDeviceIsRunning,
         kAudioDevicePropertyDeviceCanBeDefaultDevice,
         kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
         kAudioDevicePropertyLatency,
         kAudioDevicePropertySafetyOffset,
         kAudioDevicePropertyZeroTimeStampPeriod,
         kAudioDevicePropertyIsHidden:
      return UInt32(MemoryLayout<UInt32>.size)

    case kAudioDevicePropertyPreferredChannelsForStereo:
      return UInt32(MemoryLayout<UInt32>.size * 2) // left and right channel

    case kAudioObjectPropertyName,
         kAudioObjectPropertyManufacturer,
         kAudioDevicePropertyDeviceUID,
         kAudioDevicePropertyModelUID:
      return UInt32(MemoryLayout<CFString>.size)

    case kAudioObjectPropertyOwnedObjects:
      // one output stream
      return UInt32(MemoryLayout<AudioObjectID>.size)

    case kAudioDevicePropertyStreams:
      // only return stream for output scope (we have no input streams)
      return (address.mScope == kAudioObjectPropertyScopeOutput ||
        address.mScope == kAudioObjectPropertyScopeGlobal)
        ? UInt32(MemoryLayout<AudioObjectID>.size) : 0

    case kAudioObjectPropertyCustomPropertyInfoList:
      return UInt32(MemoryLayout<AudioServerPlugInCustomPropertyInfo>.size * 2)

    case kAudioDevicePropertyControlList:
      return 0 // empty list

    case kAudioDevicePropertyNominalSampleRate:
      return UInt32(MemoryLayout<Float64>.size)

    case AppFadersProperty.setVolume:
      return UInt32(VolumeCommand.totalSize)

    case AppFadersProperty.getVolume:
      return UInt32(MemoryLayout<Float32>.size)

    case kAudioDevicePropertyAvailableNominalSampleRates:
      // 3 sample rates: 44100, 48000, 96000
      return UInt32(MemoryLayout<AudioValueRange>.size * 3)

    default:
      return nil
    }
  }

  private func getDevicePropertyData(
    address: AudioObjectPropertyAddress,
    maxSize: UInt32,
    qualifierSize: UInt32 = 0,
    qualifierData: UnsafeRawPointer? = nil
  ) -> (Data, UInt32)? {
    switch address.mSelector {
    case kAudioObjectPropertyClass:
      var classID = kAudioDeviceClassID
      return (Data(bytes: &classID, count: MemoryLayout<AudioClassID>.size),
              UInt32(MemoryLayout<AudioClassID>.size))

    case kAudioObjectPropertyBaseClass:
      var classID = kAudioObjectClassID
      return (Data(bytes: &classID, count: MemoryLayout<AudioClassID>.size),
              UInt32(MemoryLayout<AudioClassID>.size))

    case kAudioObjectPropertyOwner:
      var owner = ObjectID.plugIn
      return (Data(bytes: &owner, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioObjectPropertyName:
      return cfStringPropertyData(name)

    case kAudioObjectPropertyManufacturer:
      return cfStringPropertyData(manufacturer)

    case kAudioDevicePropertyDeviceUID:
      return cfStringPropertyData(uid)

    case kAudioDevicePropertyModelUID:
      return cfStringPropertyData(modelUID)

    case kAudioDevicePropertyTransportType:
      var transport = kAudioDeviceTransportTypeVirtual
      return (Data(bytes: &transport, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyDeviceIsRunning:
      lock.lock()
      var running: UInt32 = isRunning ? 1 : 0
      lock.unlock()
      return (Data(bytes: &running, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyDeviceCanBeDefaultDevice,
         kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
      var canBe: UInt32 = 1
      return (Data(bytes: &canBe, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioObjectPropertyOwnedObjects:
      var streamID = ObjectID.outputStream
      return (Data(bytes: &streamID, count: MemoryLayout<AudioObjectID>.size),
              UInt32(MemoryLayout<AudioObjectID>.size))

    case kAudioDevicePropertyStreams:
      // only return stream for output scope (we have no input streams)
      if address.mScope == kAudioObjectPropertyScopeOutput ||
        address.mScope == kAudioObjectPropertyScopeGlobal
      {
        var streamID = ObjectID.outputStream
        return (Data(bytes: &streamID, count: MemoryLayout<AudioObjectID>.size),
                UInt32(MemoryLayout<AudioObjectID>.size))
      }
      return (Data(), 0) // no input streams

    case kAudioObjectPropertyCustomPropertyInfoList:
      var info = [
        AudioServerPlugInCustomPropertyInfo(
          mSelector: AppFadersProperty.setVolume,
          mPropertyDataType: 0,
          mQualifierDataType: 0
        ),
        AudioServerPlugInCustomPropertyInfo(
          mSelector: AppFadersProperty.getVolume,
          mPropertyDataType: 0,
          mQualifierDataType: 0
        )
      ]
      let size = MemoryLayout<AudioServerPlugInCustomPropertyInfo>.size * info.count
      return (Data(bytes: &info, count: size), UInt32(size))

    case AppFadersProperty.getVolume:
      guard qualifierSize > 0, let qualifierData else {
        return nil
      }
      let bundleID = String(cString: qualifierData.assumingMemoryBound(to: UInt8.self))
      var volume = Float32(VolumeStore.shared.getVolume(for: bundleID))
      return (Data(bytes: &volume, count: MemoryLayout<Float32>.size),
              UInt32(MemoryLayout<Float32>.size))

    case kAudioDevicePropertyControlList:
      // empty list
      return (Data(), 0)

    case kAudioDevicePropertyNominalSampleRate:
      lock.lock()
      var rate = sampleRate
      lock.unlock()
      return (Data(bytes: &rate, count: MemoryLayout<Float64>.size),
              UInt32(MemoryLayout<Float64>.size))

    case kAudioDevicePropertyAvailableNominalSampleRates:
      var rates: [AudioValueRange] = [
        AudioValueRange(mMinimum: 44100, mMaximum: 44100),
        AudioValueRange(mMinimum: 48000, mMaximum: 48000),
        AudioValueRange(mMinimum: 96000, mMaximum: 96000)
      ]
      let size = MemoryLayout<AudioValueRange>.size * rates.count
      return (Data(bytes: &rates, count: size), UInt32(size))

    case kAudioDevicePropertyLatency,
         kAudioDevicePropertySafetyOffset:
      var frames: UInt32 = 0
      return (Data(bytes: &frames, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyZeroTimeStampPeriod:
      // return sample rate as period (samples per zero timestamp)
      lock.lock()
      var period = UInt32(sampleRate)
      lock.unlock()
      return (Data(bytes: &period, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyClockDomain:
      var domain: UInt32 = 0
      return (Data(bytes: &domain, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyIsHidden:
      var hidden: UInt32 = 0 // not hidden
      return (Data(bytes: &hidden, count: MemoryLayout<UInt32>.size),
              UInt32(MemoryLayout<UInt32>.size))

    case kAudioDevicePropertyPreferredChannelsForStereo:
      var channels: [UInt32] = [1, 2] // left=1, right=2
      return (Data(bytes: &channels, count: MemoryLayout<UInt32>.size * 2),
              UInt32(MemoryLayout<UInt32>.size * 2))

    default:
      return nil
    }
  }

  // MARK: - State Management

  func setRunning(_ running: Bool) {
    lock.lock()
    isRunning = running
    lock.unlock()
    os_log(.info, log: log, "device running: %{public}@", running ? "true" : "false")
  }

  func setSampleRate(_ rate: Float64) {
    lock.lock()
    sampleRate = rate
    lock.unlock()
    os_log(.info, log: log, "sample rate changed to %f", rate)
  }

  // MARK: - SetPropertyData

  /// set property value - returns OSStatus
  func setPropertyData(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    data: UnsafeRawPointer,
    size: UInt32,
    qualifierSize: UInt32 = 0,
    qualifierData: UnsafeRawPointer? = nil
  ) -> OSStatus {
    // device sample rate change
    if objectID == ObjectID.device,
       address.mSelector == kAudioDevicePropertyNominalSampleRate
    {
      guard size >= UInt32(MemoryLayout<Float64>.size) else {
        return kAudioHardwareBadPropertySizeError
      }
      let newRate = data.load(as: Float64.self)

      // validate sample rate
      let supported: [Float64] = [44100.0, 48000.0, 96000.0]
      guard supported.contains(newRate) else {
        os_log(.error, log: log, "unsupported device sample rate: %f", newRate)
        return kAudioDeviceUnsupportedFormatError
      }

      setSampleRate(newRate)
      // also update stream sample rate (ignore result - stream validates separately)
      _ = VirtualStream.shared.setPropertyData(
        address: AudioObjectPropertyAddress(
          mSelector: kAudioStreamPropertyPhysicalFormat,
          mScope: kAudioObjectPropertyScopeGlobal,
          mElement: kAudioObjectPropertyElementMain
        ),
        data: data,
        size: size
      )
      return noErr
    }

    // set application volume
    if objectID == ObjectID.device,
       address.mSelector == AppFadersProperty.setVolume
    {
      guard size >= UInt32(VolumeCommand.totalSize) else {
        return kAudioHardwareBadPropertySizeError
      }

      // parse VolumeCommand from data
      // wire format: [bundleIDLength: UInt8] [bundleIDBytes: 255 bytes] [volume: Float32]
      let bundleIDLength = data.load(as: UInt8.self)
      guard bundleIDLength <= UInt8(VolumeCommand.maxBundleIDLength) else {
        return kAudioHardwareIllegalOperationError
      }

      let bundleIDStart = data.advanced(by: 1)
      let bundleIDData = Data(bytes: bundleIDStart, count: Int(bundleIDLength))
      guard let bundleID = String(data: bundleIDData, encoding: .utf8) else {
        return kAudioHardwareIllegalOperationError
      }

      let volumeStart = data.advanced(by: 1 + VolumeCommand.maxBundleIDLength)
      let volume = volumeStart.load(as: Float32.self)

      VolumeStore.shared.setVolume(for: bundleID, volume: volume)
      return noErr
    }

    // delegate stream properties
    if objectID == ObjectID.outputStream {
      return VirtualStream.shared.setPropertyData(address: address, data: data, size: size)
    }

    return kAudioHardwareUnknownPropertyError
  }
}

// MARK: - C Interface Exports

/// check if object has property - called from PlugInInterface.c
@_cdecl("AppFadersDriver_HasProperty")
public func driverHasProperty(
  objectID: AudioObjectID,
  clientPID: pid_t,
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement
) -> Bool {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )
  return VirtualDevice.shared.hasProperty(objectID: objectID, address: address)
}

/// check if property is settable - called from PlugInInterface.c
@_cdecl("AppFadersDriver_IsPropertySettable")
public func driverIsPropertySettable(
  objectID: AudioObjectID,
  clientPID: pid_t,
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement
) -> Bool {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )
  return VirtualDevice.shared.isPropertySettable(objectID: objectID, address: address)
}

/// get property data size - called from PlugInInterface.c
@_cdecl("AppFadersDriver_GetPropertyDataSize")
public func driverGetPropertyDataSize(
  objectID: AudioObjectID,
  clientPID: pid_t,
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  qualifierSize: UInt32,
  qualifierData: UnsafeRawPointer?,
  outSize: UnsafeMutablePointer<UInt32>?
) -> OSStatus {
  let address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: scope,
    mElement: element
  )

  guard let size = VirtualDevice.shared.getPropertyDataSize(
    objectID: objectID,
    address: address,
    qualifierSize: qualifierSize,
    qualifierData: qualifierData
  )
  else {
    return kAudioHardwareUnknownPropertyError
  }

  outSize?.pointee = size
  return noErr
}

/// get property data - called from PlugInInterface.c
@_cdecl("AppFadersDriver_GetPropertyData")
public func driverGetPropertyData(
  objectID: AudioObjectID,
  clientPID: pid_t,
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  qualifierSize: UInt32,
  qualifierData: UnsafeRawPointer?,
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
    let (data, actualSize) = VirtualDevice.shared.getPropertyData(
      objectID: objectID,
      address: address,
      maxSize: inDataSize,
      qualifierSize: qualifierSize,
      qualifierData: qualifierData
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

/// set property data - called from PlugInInterface.c
@_cdecl("AppFadersDriver_SetPropertyData")
public func driverSetPropertyData(
  objectID: AudioObjectID,
  clientPID: pid_t,
  selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope,
  element: AudioObjectPropertyElement,
  qualifierSize: UInt32,
  qualifierData: UnsafeRawPointer?,
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

  return VirtualDevice.shared.setPropertyData(
    objectID: objectID,
    address: address,
    data: data,
    size: dataSize,
    qualifierSize: qualifierSize,
    qualifierData: qualifierData
  )
}
