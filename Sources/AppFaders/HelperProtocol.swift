// HelperProtocol.swift
// XPC protocol definition for host to helper communication
//
// duplicated from AppFadersHelper/XPCProtocols.swift - must match exactly

import Foundation

/// Protocol for host app connections (read-write)
@objc protocol AppFadersHostProtocol {
  func setVolume(bundleID: String, volume: Float, reply: @escaping (NSError?) -> Void)
  func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void)
  func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void)
}
