//
//  AnyShape.swift
//  Nook
//
//  Created by Assistant on 23/09/2025.
//

import SwiftUI

/// Type-erased wrapper for Shape protocol
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = shape.path(in:)
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

