import Foundation

// NOTE: Must match AppFadersHelper/XPCProtocols.swift exactly
/// Protocol for host app connections (read-write)
@objc public protocol AppFadersHostProtocol {
  func setVolume(bundleID: String, volume: Float, reply: @escaping (NSError?) -> Void)
  func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void)
  func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void)
}
