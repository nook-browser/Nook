// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionBatchApprovalCheck.swift
//  Nook
//
//  When an install from an import list needs no sheet of its own, and when a package over an
//  installed extension is a takeover. Compiles the shipped source directly:
//
//    swiftc Nook/Managers/ExtensionManager/ExtensionBatchApproval.swift \
//           scripts/tests/ExtensionBatchApprovalCheck.swift \
//           -o /tmp/extension-batch-check && /tmp/extension-batch-check
//

import Foundation

@main
struct ExtensionBatchApprovalCheck {
    static let shown = ExtensionConsentPreview(permissions: ["storage", "tabs"], hosts: ["*://*.example.com/*", "<all_urls>"])

    static func approves(_ permissions: [String], _ hosts: [String], touching: Bool = false,
                         shown: ExtensionConsentPreview? = shown) -> Bool {
        ExtensionBatchApproval.approves(permissions: permissions, hosts: hosts, touchesInstalled: touching, shown: shown)
    }

    static func main() {
        // Nothing was shown for the row: the sheet decides, whatever the request asks.
        precondition(!approves(["storage"], [], shown: nil))
        precondition(!approves([], [], shown: nil))

        // The request is inside what was shown.
        precondition(approves(["storage"], ["<all_urls>"]))
        precondition(approves(["tabs", "storage"], ["*://*.example.com/*", "<all_urls>"]))
        precondition(approves([], []))

        // One permission or one host beyond it, the sheet.
        precondition(!approves(["storage", "cookies"], []))
        precondition(!approves([], ["*://*.other.com/*"]))
        precondition(!approves(["storage"], ["*://*.example.com/*", "*://*.other.com/*"]))

        // An empty preview shows "no special permissions": a request with some is not covered.
        let none = ExtensionConsentPreview(permissions: [], hosts: [])
        precondition(approves([], [], shown: none))
        precondition(!approves(["storage"], [], shown: none))

        // It replaces, updates or carries an installed copy: the sheet, even when it matches.
        precondition(!approves(["storage"], ["<all_urls>"], touching: true))
        precondition(!approves([], [], touching: true, shown: none))

        // Takeover: a store build over a store build is an update, a file over anything is not a takeover.
        let safari = ExtensionSourceShape.safari(appPath: "/Applications/A.app")
        precondition(!ExtensionSourceShape.takesOver(from: .store, to: .store))
        precondition(!ExtensionSourceShape.takesOver(from: .file, to: .store))
        precondition(!ExtensionSourceShape.takesOver(from: .file, to: safari))
        precondition(!ExtensionSourceShape.takesOver(from: .file, to: .file))

        // A Safari import with no recorded app path meets its app for the first time: not a takeover.
        precondition(!ExtensionSourceShape.takesOver(from: .safari(appPath: nil), to: safari))
        precondition(!ExtensionSourceShape.takesOver(from: .safari(appPath: nil), to: .safari(appPath: nil)))

        // The same app, no. Another app or a moved one, yes.
        precondition(!ExtensionSourceShape.takesOver(from: safari, to: safari))
        precondition(ExtensionSourceShape.takesOver(from: safari, to: .safari(appPath: "/Applications/B.app")))
        precondition(ExtensionSourceShape.takesOver(from: safari, to: .safari(appPath: nil)))

        // A different kind of source over a store or Safari install is a takeover, with or without a path.
        precondition(ExtensionSourceShape.takesOver(from: .store, to: safari))
        precondition(ExtensionSourceShape.takesOver(from: .store, to: .file))
        precondition(ExtensionSourceShape.takesOver(from: safari, to: .store))
        precondition(ExtensionSourceShape.takesOver(from: .safari(appPath: nil), to: .store))
        precondition(ExtensionSourceShape.takesOver(from: .safari(appPath: nil), to: .file))

        // A previous version left in its backup folder by a quit in the middle of an update.
        // Nothing arrived in its place: it goes back.
        precondition(ExtensionBackup.restores(currentVersion: nil, backupVersion: "4.0", recordVersion: "4.0"))
        precondition(ExtensionBackup.restores(currentVersion: nil, backupVersion: nil, recordVersion: nil))
        // The new files arrived but the record still names the old version: the old files go back.
        precondition(ExtensionBackup.restores(currentVersion: "5.0", backupVersion: "4.0", recordVersion: "4.0"))
        // The record names the new version: the update finished, and the backup is only leftovers.
        precondition(!ExtensionBackup.restores(currentVersion: "5.0", backupVersion: "4.0", recordVersion: "5.0"))
        // No record, or a backup that cannot be read, beside files that are there: leave them.
        precondition(!ExtensionBackup.restores(currentVersion: "5.0", backupVersion: "4.0", recordVersion: nil))
        precondition(!ExtensionBackup.restores(currentVersion: "5.0", backupVersion: nil, recordVersion: "4.0"))
        print("ok")
    }
}
