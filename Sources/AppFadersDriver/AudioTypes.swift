// AudioTypes.swift
// Shared types for the AppFaders HAL driver
//
// defines configuration and format types used across driver components

import CoreAudio

// MARK: - Device Configuration

/// configuration for the virtual audio device
/// matches the device properties exposed to coreaudiod
public struct AudioDeviceConfiguration: Sendable {
  public let name: String
  public let uid: String
  public let manufacturer: String
  public let sampleRates: [Double]
  public let channelCount: UInt32

  public init(
    name: String,
    uid: String,
    manufacturer: String,
    sampleRates: [Double],
    channelCount: UInt32
  ) {
    self.name = name
    self.uid = uid
    self.manufacturer = manufacturer
    self.sampleRates = sampleRates
    self.channelCount = channelCount
  }

  /// default configuration for AppFaders virtual device
  public static let `default` = AudioDeviceConfiguration(
    name: "AppFaders",
    uid: "com.fbreidenbach.appfaders.virtualdevice",
    manufacturer: "AppFaders",
    sampleRates: [44100.0, 48000.0, 96000.0],
    channelCount: 2
  )
}

// MARK: - Stream Format

/// audio stream format specification
/// wraps the key properties from AudioStreamBasicDescription
public struct StreamFormat: Sendable, Equatable {
  public let sampleRate: Double
  public let channelCount: UInt32
  public let bitsPerChannel: UInt32
  public let formatID: AudioFormatID

  public init(
    sampleRate: Double,
    channelCount: UInt32,
    bitsPerChannel: UInt32,
    formatID: AudioFormatID
  ) {
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.bitsPerChannel = bitsPerChannel
    self.formatID = formatID
  }

  /// default format: 48kHz stereo 32-bit float PCM
  public static let `default` = StreamFormat(
    sampleRate: 48000.0,
    channelCount: 2,
    bitsPerChannel: 32,
    formatID: kAudioFormatLinearPCM
  )

  /// bytes per frame (channels * bytes per sample)
  public var bytesPerFrame: UInt32 {
    channelCount * (bitsPerChannel / 8)
  }

  /// convert to CoreAudio AudioStreamBasicDescription
  public func toASBD() -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: formatID,
      mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
      mBytesPerPacket: bytesPerFrame,
      mFramesPerPacket: 1,
      mBytesPerFrame: bytesPerFrame,
      mChannelsPerFrame: channelCount,
      mBitsPerChannel: bitsPerChannel,
      mReserved: 0
    )
  }

  /// create from CoreAudio AudioStreamBasicDescription
  public init(from asbd: AudioStreamBasicDescription) {
    sampleRate = asbd.mSampleRate
    channelCount = asbd.mChannelsPerFrame
    bitsPerChannel = asbd.mBitsPerChannel
    formatID = asbd.mFormatID
  }
}

// MARK: - Supported Formats

public extension AudioDeviceConfiguration {
  /// generate all supported StreamFormats for this device
  var supportedFormats: [StreamFormat] {
    sampleRates.map { rate in
      StreamFormat(
        sampleRate: rate,
        channelCount: channelCount,
        bitsPerChannel: 32,
        formatID: kAudioFormatLinearPCM
      )
    }
  }
}

