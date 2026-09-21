// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+AudioDevice+iOS.swift
//  NookWeb
//
//  iOS has no hardware audio object API. Playing state comes from the page's media script alone.
//

#if os(iOS)
import Foundation

extension PageSession {
    func setupCoreAudioPropertyListeners() {}
    func removeCoreAudioPropertyListeners() {}
    func isDefaultAudioDeviceActive() -> Bool { false }
}
#endif
