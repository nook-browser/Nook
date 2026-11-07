// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconKeyShim.swift
//  Nook
//
//  Stand-ins for Platform.swift so FaviconCache.swift compiles alone in FaviconKeyCheck.
//

import AppKit
import SwiftUI

public typealias PlatformImage = NSImage
extension Image { public init(platformImage: PlatformImage) { self.init(nsImage: platformImage) } }
extension NSImage {
    func pngData() -> Data? { nil }
    convenience init?(data: Data, _ x: Int = 0) { self.init(data: data) }
}
