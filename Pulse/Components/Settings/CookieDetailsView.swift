//
//  CookieDetailsView.swift
//  Pulse
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

struct CookieDetailsView: View {
    let cookie: CookieInfo
    let cookieManager: CookieManager
    @Environment(\.dismiss) private var dismiss
    
    private let details: [String: String]
    
    init(cookie: CookieInfo, cookieManager: CookieManager) {
        self.cookie = cookie
        self.cookieManager = cookieManager
        self.details = cookieManager.getCookieDetails(cookie)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info Section
                    sectionView(title: "Basic Information") {
                        detailRow("Name", cookie.name, isMonospace: true)
                        detailRow("Domain", cookie.displayDomain)
                        detailRow("Path", cookie.path, isMonospace: true)
                        detailRow("Size", cookie.sizeDescription)
                    }
                    
                    // Security Section
                    sectionView(title: "Security") {
                        detailRow("Secure", cookie.isSecure ? "Yes" : "No", 
                                color: cookie.isSecure ? .green : .red)
                        detailRow("HTTP Only", cookie.isHTTPOnly ? "Yes" : "No",
                                color: cookie.isHTTPOnly ? .green : .orange)
                        detailRow("Same Site Policy", cookie.sameSitePolicy)
                    }
                    
                    // Expiration Section
                    sectionView(title: "Expiration") {
                        detailRow("Type", cookie.isSessionCookie ? "Session Cookie" : "Persistent Cookie")
                        detailRow("Expires", cookie.expirationStatus)
                        
                        if let expiresDate = cookie.expiresDate {
                            let isExpired = expiresDate < Date()
                            detailRow("Status", isExpired ? "Expired" : "Valid",
                                    color: isExpired ? .red : .green)
                        }
                    }
                    
                    // Value Section
                    sectionView(title: "Value") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cookie Value:")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(cookie.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .padding()
            }
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 500)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookie Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(cookie.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Button("Copy Value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cookie.value, forType: .string)
            }
            .buttonStyle(.bordered)
            
            Button("Copy Details") {
                let detailsText = formatDetailsForClipboard()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(detailsText, forType: .string)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Delete Cookie", role: .destructive) {
                Task {
                    await cookieManager.deleteCookie(cookie)
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Section View
    
    private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Detail Row
    
    private func detailRow(_ label: String, _ value: String, isMonospace: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .font(isMonospace ? .system(.body, design: .monospaced) : .body)
                .foregroundColor(color ?? .primary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDetailsForClipboard() -> String {
        var text = "Cookie Details for \(cookie.name)\n"
        text += String(repeating: "=", count: 40) + "\n\n"
        
        for (key, value) in details.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\n"
        }
        
        text += "\nFull Value:\n\(cookie.value)"
        
        return text
    }
}

#Preview {
    let sampleCookie = CookieInfo(from: HTTPCookie(properties: [
        .name: "session_id",
        .value: "abc123def456ghi789",
        .domain: ".example.com",
        .path: "/",
        .secure: true,
        .expires: Date().addingTimeInterval(86400)
    ])!)
    
    return CookieDetailsView(cookie: sampleCookie, cookieManager: CookieManager())
}
