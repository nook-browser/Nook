// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionBatchApproval.swift
//  Nook
//
//  Two install rules with no UI in them: when an install from an import list may go ahead without
//  its own sheet, and when a package arriving over an installed extension is a takeover.
//  Foundation only, so a check compiles it directly.
//

import Foundation

/// The permissions and site access a list row showed for an extension.
struct ExtensionConsentPreview: Equatable, Sendable {
    let permissions: [String]
    let hosts: [String]
}

enum ExtensionBatchApproval {
    /// True only when the row showed lines, the request asks for nothing beyond them, and the
    /// install leaves every installed extension alone. Anything else goes to the consent sheet.
    static func approves(
        permissions: [String], hosts: [String], touchesInstalled: Bool, shown: ExtensionConsentPreview?
    ) -> Bool {
        guard !touchesInstalled, let shown else { return false }
        return Set(permissions).isSubset(of: shown.permissions) && Set(hosts).isSubset(of: shown.hosts)
    }
}

/// Where a package came from, without the types the app builds it from.
enum ExtensionSourceShape: Equatable {
    case store
    case safari(appPath: String?)
    case file

    /// Whether `new` arriving over an installed `old` is another extension claiming its ID, so
    /// its data and grants must not carry over unasked. An import from before app paths were
    /// recorded has none, and the first path it meets is the same extension seen again.
    static func takesOver(from old: Self, to new: Self) -> Bool {
        switch (old, new) {
        case (.store, .store), (.file, _): false
        case (.safari(nil), .safari): false
        case let (.safari(oldApp?), .safari(newApp?)): oldApp != newApp
        default: true
        }
    }
}
