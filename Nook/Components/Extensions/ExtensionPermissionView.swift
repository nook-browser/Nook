//
//  ExtensionPermissionView.swift
//  Nook
//
//  Created for WKWebExtension permission management
//

import SwiftUI
import WebKit

@available(macOS 15.4, *)
struct ExtensionPermissionView: View {
    let extensionName: String
    let requestedPermissions: [String]
    let optionalPermissions: [String]
    let requestedHostPermissions: [String]
    let optionalHostPermissions: [String]
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
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)
                    Image(nsImage: extensionLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }

                
            
            }
            Text("Add the \"\(extensionName)\"extension to Nook?")
                .font(.system(size: 16, weight: .semibold))
            
            Text("It can:")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(requestedPermissions, id: \.self) { permission in
                    let message = getPermissionDescription(permission)
                    Text("•  \(message)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack{
                Button("Cancel") {
                    onDeny()
                }
                Spacer()
                Button("Add Extension") {
                    onGrant()
                }
            }
        }
        .padding(20)
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
        default:
            return "Access \(permission) functionality"
        }
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
