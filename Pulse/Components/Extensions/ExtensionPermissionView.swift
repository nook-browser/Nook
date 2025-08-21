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
    let requestedPermissions: [String]
    let optionalPermissions: [String]
    let requestedHostPermissions: [String]
    let optionalHostPermissions: [String]
    let onGrant: (Set<String>, Set<String>) -> Void
    let onDeny: () -> Void
    
    @State private var selectedPermissions: Set<String> = []
    @State private var selectedHostPermissions: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
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
                    if !requestedPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requested Permissions")
                                .font(.headline)
                            ForEach(requestedPermissions, id: \.self) { permission in
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
                    if !optionalPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Optional Permissions")
                                .font(.headline)
                            ForEach(optionalPermissions, id: \.self) { permission in
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
                    
                    if !requestedHostPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requested Website Access")
                                .font(.headline)
                            ForEach(requestedHostPermissions, id: \.self) { host in
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
                    if !optionalHostPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Optional Website Access")
                                .font(.headline)
                            ForEach(optionalHostPermissions, id: \.self) { host in
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
            for permission in requestedPermissions {
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
            requestedPermissions: ["storage", "activeTab", "tabs"],
            optionalPermissions: ["notifications"],
            requestedHostPermissions: ["https://*.google.com/*"],
            optionalHostPermissions: ["https://github.com/*"],
            onGrant: { _, _ in },
            onDeny: { }
        )
    }
}
