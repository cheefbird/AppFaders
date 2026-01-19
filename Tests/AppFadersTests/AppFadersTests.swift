import SimplyCoreAudio
import Testing

/// Placeholder tests - full implementation in Tasks 13-14
@Test func simplyCoreAudioImports() async throws {
  // Verify SimplyCoreAudio dependency is properly configured
  let sca = SimplyCoreAudio()
  #expect(sca.allDevices.count >= 0)
}
