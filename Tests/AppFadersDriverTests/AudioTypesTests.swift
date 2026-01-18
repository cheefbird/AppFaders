// AudioTypesTests.swift
// Unit tests for AudioTypes and AudioRingBuffer
//
// uses Swift Testing framework (@Test, #expect)

@testable import AppFadersDriver
import CoreAudio
import Testing

// MARK: - AudioDeviceConfiguration Tests

@Suite("AudioDeviceConfiguration")
struct AudioDeviceConfigurationTests {
  @Test("default configuration has expected values")
  func defaultConfiguration() {
    let config = AudioDeviceConfiguration.default

    #expect(config.name == "AppFaders")
    #expect(config.uid == "com.fbreidenbach.appfaders.virtualdevice")
    #expect(config.manufacturer == "AppFaders")
    #expect(config.sampleRates == [44100.0, 48000.0, 96000.0])
    #expect(config.channelCount == 2)
  }

  @Test("custom configuration initializes correctly")
  func customConfiguration() {
    let config = AudioDeviceConfiguration(
      name: "Test Device",
      uid: "com.test.device",
      manufacturer: "Test Co",
      sampleRates: [22050.0, 44100.0],
      channelCount: 6
    )

    #expect(config.name == "Test Device")
    #expect(config.uid == "com.test.device")
    #expect(config.manufacturer == "Test Co")
    #expect(config.sampleRates == [22050.0, 44100.0])
    #expect(config.channelCount == 6)
  }

  @Test("supportedFormats generates correct StreamFormats")
  func supportedFormats() {
    let config = AudioDeviceConfiguration.default
    let formats = config.supportedFormats

    #expect(formats.count == 3)

    // check each format matches expected sample rate
    #expect(formats[0].sampleRate == 44100.0)
    #expect(formats[1].sampleRate == 48000.0)
    #expect(formats[2].sampleRate == 96000.0)

    // all formats should have same channel count and bit depth
    for format in formats {
      #expect(format.channelCount == 2)
      #expect(format.bitsPerChannel == 32)
      #expect(format.formatID == kAudioFormatLinearPCM)
    }
  }
}

// MARK: - StreamFormat Tests

@Suite("StreamFormat")
struct StreamFormatTests {
  @Test("default format has expected values")
  func defaultFormat() {
    let format = StreamFormat.default

    #expect(format.sampleRate == 48000.0)
    #expect(format.channelCount == 2)
    #expect(format.bitsPerChannel == 32)
    #expect(format.formatID == kAudioFormatLinearPCM)
  }

  @Test("custom format initializes correctly")
  func customFormat() {
    let format = StreamFormat(
      sampleRate: 96000.0,
      channelCount: 8,
      bitsPerChannel: 24,
      formatID: kAudioFormatLinearPCM
    )

    #expect(format.sampleRate == 96000.0)
    #expect(format.channelCount == 8)
    #expect(format.bitsPerChannel == 24)
  }

  @Test("bytesPerFrame calculation is correct")
  func bytesPerFrame() {
    // stereo 32-bit: 2 channels * 4 bytes = 8
    let stereo32 = StreamFormat.default
    #expect(stereo32.bytesPerFrame == 8)

    // mono 16-bit: 1 channel * 2 bytes = 2
    let mono16 = StreamFormat(
      sampleRate: 44100.0,
      channelCount: 1,
      bitsPerChannel: 16,
      formatID: kAudioFormatLinearPCM
    )
    #expect(mono16.bytesPerFrame == 2)

    // 8-channel 32-bit: 8 channels * 4 bytes = 32
    let surround = StreamFormat(
      sampleRate: 48000.0,
      channelCount: 8,
      bitsPerChannel: 32,
      formatID: kAudioFormatLinearPCM
    )
    #expect(surround.bytesPerFrame == 32)
  }

  @Test("toASBD produces correct AudioStreamBasicDescription")
  func toASBD() {
    let format = StreamFormat.default
    let asbd = format.toASBD()

    #expect(asbd.mSampleRate == 48000.0)
    #expect(asbd.mFormatID == kAudioFormatLinearPCM)
    #expect(asbd.mFormatFlags == kAudioFormatFlagsNativeFloatPacked)
    #expect(asbd.mChannelsPerFrame == 2)
    #expect(asbd.mBitsPerChannel == 32)
    #expect(asbd.mBytesPerFrame == 8)
    #expect(asbd.mBytesPerPacket == 8)
    #expect(asbd.mFramesPerPacket == 1)
  }

  @Test("init from ASBD round-trips correctly")
  func initFromASBD() {
    let original = StreamFormat(
      sampleRate: 96000.0,
      channelCount: 6,
      bitsPerChannel: 32,
      formatID: kAudioFormatLinearPCM
    )

    let asbd = original.toASBD()
    let restored = StreamFormat(from: asbd)

    #expect(restored.sampleRate == original.sampleRate)
    #expect(restored.channelCount == original.channelCount)
    #expect(restored.bitsPerChannel == original.bitsPerChannel)
    #expect(restored.formatID == original.formatID)
  }

  @Test("Equatable works correctly")
  func equatable() {
    let a = StreamFormat.default
    let b = StreamFormat(
      sampleRate: 48000.0,
      channelCount: 2,
      bitsPerChannel: 32,
      formatID: kAudioFormatLinearPCM
    )
    let c = StreamFormat(
      sampleRate: 44100.0,
      channelCount: 2,
      bitsPerChannel: 32,
      formatID: kAudioFormatLinearPCM
    )

    #expect(a == b)
    #expect(a != c)
  }
}

// MARK: - AudioRingBuffer Tests

@Suite("AudioRingBuffer")
struct AudioRingBufferTests {
  @Test("write and read basic operation")
  func writeRead() {
    let buffer = AudioRingBuffer()

    // write 10 frames of stereo audio (20 samples)
    let input: [Float] = Array(repeating: 0.5, count: 20)
    let written = input.withUnsafeBufferPointer { ptr in
      buffer.write(frames: ptr.baseAddress!, frameCount: 10)
    }
    #expect(written == 10)

    // read back
    var output = [Float](repeating: 0.0, count: 20)
    let read = output.withUnsafeMutableBufferPointer { ptr in
      buffer.read(into: ptr.baseAddress!, frameCount: 10)
    }
    #expect(read == 10)

    // verify data matches
    for i in 0..<20 {
      #expect(output[i] == 0.5)
    }
  }

  @Test("underflow fills remainder with silence")
  func underflow() {
    let buffer = AudioRingBuffer()

    // write 5 frames
    let input: [Float] = Array(1...10).map { Float($0) }
    _ = input.withUnsafeBufferPointer { ptr in
      buffer.write(frames: ptr.baseAddress!, frameCount: 5)
    }

    // read 10 frames (5 more than available)
    var output = [Float](repeating: -1.0, count: 20)
    let read = output.withUnsafeMutableBufferPointer { ptr in
      buffer.read(into: ptr.baseAddress!, frameCount: 10)
    }

    // should only get 5 frames of actual data
    #expect(read == 5)

    // first 10 samples should be the data
    for i in 0..<10 {
      #expect(output[i] == Float(i + 1))
    }

    // remaining samples should be silence (0.0)
    for i in 10..<20 {
      #expect(output[i] == 0.0)
    }
  }

  @Test("overflow drops excess data")
  func overflow() {
    let buffer = AudioRingBuffer()

    // ring buffer capacity is 8192 frames
    // try to write more than capacity
    let largeInput = [Float](repeating: 1.0, count: 8192 * 2 * 2) // double capacity in samples

    let written = largeInput.withUnsafeBufferPointer { ptr in
      buffer.write(frames: ptr.baseAddress!, frameCount: 8192 * 2)
    }

    // should write less than requested due to capacity
    #expect(written < 8192 * 2)
    #expect(written > 0)
  }

  @Test("wrap-around handles index correctly")
  func wrapAround() {
    let buffer = AudioRingBuffer()

    // write and read multiple times to force wrap-around
    let chunk: [Float] = Array(repeating: 0.25, count: 2000 * 2) // 2000 frames
    var readBuffer = [Float](repeating: 0.0, count: 2000 * 2)

    // do 10 iterations to wrap around the 8192 frame buffer
    for iteration in 0..<10 {
      let written = chunk.withUnsafeBufferPointer { ptr in
        buffer.write(frames: ptr.baseAddress!, frameCount: 2000)
      }
      #expect(written == 2000, "iteration \(iteration) write failed")

      let read = readBuffer.withUnsafeMutableBufferPointer { ptr in
        buffer.read(into: ptr.baseAddress!, frameCount: 2000)
      }
      #expect(read == 2000, "iteration \(iteration) read failed")

      // verify data integrity after wrap
      for i in 0..<(2000 * 2) {
        #expect(readBuffer[i] == 0.25, "data corruption at iteration \(iteration), index \(i)")
      }
    }
  }

  @Test("reset clears buffer state")
  func reset() {
    let buffer = AudioRingBuffer()

    // write some data
    let input: [Float] = Array(repeating: 0.75, count: 100)
    _ = input.withUnsafeBufferPointer { ptr in
      buffer.write(frames: ptr.baseAddress!, frameCount: 50)
    }

    // reset
    buffer.reset()

    // read should return 0 frames (no data available)
    var output = [Float](repeating: -1.0, count: 20)
    let read = output.withUnsafeMutableBufferPointer { ptr in
      buffer.read(into: ptr.baseAddress!, frameCount: 10)
    }

    #expect(read == 0)
    // read fills remainder with silence (0.0) on underflow
    for i in 0..<20 {
      #expect(output[i] == 0.0)
    }
  }
}
