// Protocols.swift
// XPC protocol definitions for host and driver clients

import Foundation

/// Protocol for host app connections (read-write)
@objc protocol AppFadersHostProtocol {
    func setVolume(bundleID: String, volume: Float, reply: @escaping (NSError?) -> Void)
    func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void)
    func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void)
}

/// Protocol for driver connections (read-only)
@objc protocol AppFadersDriverProtocol {
    func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void)
    func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void)
}
