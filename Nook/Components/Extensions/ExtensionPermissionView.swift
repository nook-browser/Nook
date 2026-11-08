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
                Text("It does not request any special permissions.")
                    .font(NookDesign.Font.label)
                    .foregroundColor(.secondary)
            } else {
                Text("It can:")
                    .font(NookDesign.Font.label)
                    .foregroundColor(.secondary)
                ViewThatFits(in: .vertical) {
                    permissionList
                    ScrollView {
                        permissionList
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

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hostLine {
                Text("•  \(hostLine)")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.secondary)
            }
            ForEach(requestedPermissions, id: \.self) { permission in
                Text("•  \(getPermissionDescription(permission))")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// One line summarizing site access, Chrome-style.
    private var hostLine: String? {
        guard !requestedHostPermissions.isEmpty else { return nil }
        let hosts = requestedHostPermissions.map { pattern -> String in
            guard let range = pattern.range(of: "://") else { return pattern }
            let rest = pattern[range.upperBound...]
            return String(rest.prefix { $0 != "/" })
        }
        if requestedHostPermissions.contains("<all_urls>") || hosts.contains("*") {
            return "Read and change all your data on all websites"
        }
        let unique = Array(Set(hosts)).sorted()
        let shown = unique.prefix(5).joined(separator: ", ")
        let more = unique.count > 5 ? " and \(unique.count - 5) more" : ""
        return "Read and change your data on \(shown)\(more)"
    }

    private func getPermissionDescription(_ permission: String) -> String {
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
        case "alarms", "idle", "i18n", "runtime", "commands", "sidePanel", "offscreen", "action":
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
