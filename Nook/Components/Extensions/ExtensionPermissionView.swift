// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionPermissionView.swift
//  Nook
//
//  Created for WKWebExtension permission management
//

import SwiftUI
import NookDesign
import WebKit

struct ExtensionPermissionView: View {
    let extensionName: String
    let requestedPermissions: [String]
    let optionalPermissions: [String]
    let requestedHostPermissions: [String]
    let optionalHostPermissions: [String]
    var isRuntimeRequest: Bool = false
    var isUpdate: Bool = false
    var source: ExtensionSource? = nil
    var version: String = ""
    var replacing: InstalledExtension? = nil
    let onGrant: () -> Void
    let onDeny: () -> Void
    let extensionLogo: NSImage

    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    Image("nook-logo-1024")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                    Image(systemName: "arrow.left")
                        .font(NookDesign.Font.display)
                        .foregroundColor(.secondary)
                    Image(nsImage: extensionLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }

                
            
            }
            Text(title)
                .font(NookDesign.Font.title)

            if let replacing, let source {
                switchDetails(from: replacing, to: source)
            } else if let source {
                Text(source.consentLine)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.secondary)
            }

            if requestedPermissions.isEmpty && requestedHostPermissions.isEmpty {
                lines
            } else {
                Text("It can:")
                    .font(NookDesign.Font.label)
                    .foregroundColor(.secondary)
                ViewThatFits(in: .vertical) {
                    lines
                    ScrollView {
                        lines
                    }
                    .scrollIndicators(.visible)
                }
                .frame(maxHeight: 240)
            }
            HStack{
                Button("Cancel") {
                    onDeny()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(grantTitle) {
                    onGrant()
                }
            }
        }
        .padding(20)
    }

    private var lines: ExtensionConsentLines {
        ExtensionConsentLines(permissions: requestedPermissions, hosts: requestedHostPermissions)
    }

    private func switchDetails(from old: InstalledExtension, to new: ExtensionSource) -> some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
            Grid(alignment: .leading, horizontalSpacing: NookDesign.Spacing.lg, verticalSpacing: NookDesign.Spacing.xs) {
                GridRow {
                    Text("Now").foregroundStyle(.secondary)
                    Text(old.source.summary(version: old.version))
                }
                GridRow {
                    Text("After").foregroundStyle(.secondary)
                    Text(new.summary(version: version))
                }
            }
            .font(NookDesign.Font.label)

            Text("\(extensionName)'s data in Nook doesn't carry over, so you may need to sign in to \(extensionName) again. The \(old.source.versionName) version is removed once the \(new.versionName) version is installed.")
                .font(NookDesign.Font.bodyRegular)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grantTitle: String {
        if isRuntimeRequest { return "Allow" }
        if replacing != nil { return "Switch" }
        return isUpdate ? "Update" : "Add Extension"
    }

    private var title: String {
        if isRuntimeRequest { return "\"\(extensionName)\" wants additional permissions" }
        if replacing != nil, let source { return "Switch \"\(extensionName)\" to the \(source.versionName) version?" }
        if isUpdate { return "The new version of \"\(extensionName)\" needs more permissions" }
        return "Add the \"\(extensionName)\" extension to Nook?"
    }
}

/// The permission and site-access lines of the consent sheet. An import list shows the same
/// lines under each row.
struct ExtensionConsentLines: View {
    let permissions: [String]
    let hosts: [String]
    var font: SwiftUI.Font = NookDesign.Font.label
    var spacing: CGFloat = 12

    var body: some View {
        if permissions.isEmpty && hosts.isEmpty {
            Text("It does not request any special permissions.")
                .font(font)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                if let hostLine {
                    Text("•  \(hostLine)")
                        .font(font)
                        .foregroundStyle(.secondary)
                }
                ForEach(permissions, id: \.self) { permission in
                    Text("•  \(Self.description(of: permission))")
                        .font(font)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One line summarizing site access, Chrome-style.
    private var hostLine: String? {
        guard !hosts.isEmpty else { return nil }
        let names = hosts.map { pattern -> String in
            guard let range = pattern.range(of: "://") else { return pattern }
            let rest = pattern[range.upperBound...]
            return String(rest.prefix { $0 != "/" })
        }
        if hosts.contains("<all_urls>") || names.contains("*") {
            return "Read and change all your data on all websites"
        }
        let unique = Array(Set(names)).sorted()
        let shown = unique.prefix(5).joined(separator: ", ")
        let more = unique.count > 5 ? " and \(unique.count - 5) more" : ""
        return "Read and change your data on \(shown)\(more)"
    }

    static func description(of permission: String) -> String {
        switch permission {
        case "storage":
            return "Store and retrieve data locally"
        case "activeTab":
            return "Access the currently active tab when you click the extension"
        case "tabs":
            return "Access basic information about all tabs"
        case "bookmarks":
            return "Read and modify your bookmarks"
        case "history":
            return "Access your browsing history"
        case "cookies":
            return "Access cookies for websites"
        case "webNavigation":
            return "Monitor and analyze web page navigation"
        case "scripting":
            return "Inject scripts into web pages"
        case "notifications":
            return "Display notifications"
        case "nativeMessaging":
            return "Communicate with cooperating native applications"
        case "clipboardRead":
            return "Read data you copy and paste"
        case "clipboardWrite":
            return "Modify data you copy and paste"
        case "webRequest", "declarativeNetRequest", "declarativeNetRequestWithHostAccess":
            return "Block or modify network requests"
        case "downloads":
            return "Manage your downloads"
        case "contextMenus", "menus":
            return "Add items to context menus"
        case "unlimitedStorage":
            return "Store an unlimited amount of data"
        case "management":
            return "See your other installed extensions"
        case "identity":
            return "Sign you in to web services, sometimes in the background"
        case "idle":
            return "See when you are away from your Mac"
        case "offscreen":
            return "Run a hidden page in the background"
        case "sidePanel":
            return "Open a panel of its own"
        case "alarms", "i18n", "runtime", "commands", "action":
            return "Run in the background and respond to browser events"
        default:
            return "Access \(permission) functionality"
        }
    }
}

extension ExtensionPermissionView {
    init(consent: InstallConsent, onGrant: @escaping () -> Void, onDeny: @escaping () -> Void) {
        self.init(
            extensionName: consent.name,
            requestedPermissions: consent.permissions,
            optionalPermissions: [],
            requestedHostPermissions: consent.hosts,
            optionalHostPermissions: [],
            isUpdate: consent.isUpdate,
            source: consent.source,
            version: consent.version,
            replacing: consent.replacing,
            onGrant: onGrant,
            onDeny: onDeny,
            extensionLogo: consent.logo
        )
    }
}

#Preview {
    ExtensionPermissionView(
        extensionName: "Sample Extension",
        requestedPermissions: ["storage", "activeTab", "tabs"],
        optionalPermissions: ["notifications"],
        requestedHostPermissions: ["https://*.google.com/*"],
        optionalHostPermissions: ["https://github.com/*"],
        onGrant: { },
        onDeny: { },
        extensionLogo: NSImage(imageLiteralResourceName: "nook-logo-1024")
    )
}
