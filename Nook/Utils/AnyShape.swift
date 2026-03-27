//
//  AnyShape.swift
//  Nook
//
//  Created by Assistant on 23/09/2025.
//

import SwiftUI

/// Type-erased wrapper for Shape protocol
struct AnyShape: Shape, @unchecked Sendable {
    private let _path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        let pathFn = shape.path(in:)
        _path = { rect in pathFn(rect) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

