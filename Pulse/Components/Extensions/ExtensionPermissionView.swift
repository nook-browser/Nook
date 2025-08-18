//
//  ExtensionPermissionView.swift
//  Pulse
//
//  Created for WKWebExtension permission management
//

import SwiftUI
import WebKit

@available(macOS 15.4, *)
struct ExtensionPermissionView: View {
    let extensionName: String
    let permissions: [String]
    let hostPermissions: [String]
    let onGrant: (Set<String>, Set<String>) -> Void
    let onDeny: () -> Void
    
    @State private var selectedPermissions: Set<String> = []
    @State private var selectedHostPermissions: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Extension Permission Request")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\"\(extensionName)\" wants to:")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Standard Permissions
                    if !permissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Permissions")
                                .font(.headline)
                            
                            ForEach(permissions, id: \.self) { permission in
                                PermissionRowView(
                                    permission: permission,
                                    description: getPermissionDescription(permission),
                                    isSelected: Binding(
                                        get: { selectedPermissions.contains(permission) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedPermissions.insert(permission)
                                            } else {
                                                selectedPermissions.remove(permission)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }
                    
                    // Host Permissions
                    if !hostPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Website Access")
                                .font(.headline)
                            
                            ForEach(hostPermissions, id: \.self) { host in
                                PermissionRowView(
                                    permission: host,
                                    description: getHostPermissionDescription(host),
                                    isSelected: Binding(
                                        get: { selectedHostPermissions.contains(host) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedHostPermissions.insert(host)
                                            } else {
                                                selectedHostPermissions.remove(host)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Deny") {
                    onDeny()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Allow Selected") {
                    onGrant(selectedPermissions, selectedHostPermissions)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(selectedPermissions.isEmpty && selectedHostPermissions.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500, height: 600)
        .onAppear {
            // Auto-select safe permissions
            for permission in permissions {
                if isSafePermission(permission) {
                    selectedPermissions.insert(permission)
                }
            }
        }
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
    
    private func getHostPermissionDescription(_ host: String) -> String {
        if host == "<all_urls>" {
            return "Access all websites"
        } else if host.hasPrefix("*://") {
            let domain = String(host.dropFirst(4))
            return "Access all pages on \(domain)"
        } else {
            return "Access \(host)"
        }
    }
    
    private func isSafePermission(_ permission: String) -> Bool {
        let safePermissions = ["storage", "notifications"]
        return safePermissions.contains(permission)
    }
}

struct PermissionRowView: View {
    let permission: String
    let description: String
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(permission)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@available(macOS 15.4, *)
struct ExtensionPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        ExtensionPermissionView(
            extensionName: "Sample Extension",
            permissions: ["storage", "activeTab", "tabs"],
            hostPermissions: ["https://*.google.com/*", "https://github.com/*"],
            onGrant: { _, _ in },
            onDeny: { }
        )
    }
}