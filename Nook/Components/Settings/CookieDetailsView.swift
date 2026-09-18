// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  CookieDetailsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import NookDesign

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
            Form {
                Section("Cookie Details") {
                    LabeledContent("Name") {
                        Text(cookie.name)
                            .font(NookDesign.Font.body.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Domain") {
                        Text(cookie.displayDomain)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Path") {
                        Text(cookie.path)
                            .font(NookDesign.Font.body.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Size") {
                        Text(cookie.sizeDescription)
                            .textSelection(.enabled)
                    }
                }

                Section("Security") {
                    LabeledContent("Secure") {
                        Text(cookie.isSecure ? "Yes" : "No")
                            .foregroundStyle(cookie.isSecure ? .green : .red)
                            .textSelection(.enabled)
                    }
                    LabeledContent("HTTP Only") {
                        Text(cookie.isHTTPOnly ? "Yes" : "No")
                            .foregroundStyle(cookie.isHTTPOnly ? .green : .orange)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Same Site Policy") {
                        Text(cookie.sameSitePolicy)
                            .textSelection(.enabled)
                    }
                }

                Section("Expiration") {
                    LabeledContent("Type") {
                        Text(cookie.isSessionCookie ? "Session Cookie" : "Persistent Cookie")
                            .textSelection(.enabled)
                    }
                    LabeledContent("Expires") {
                        Text(cookie.expirationStatus)
                            .textSelection(.enabled)
                    }

                    if let expiresDate = cookie.expiresDate {
                        let isExpired = expiresDate < Date()
                        LabeledContent("Status") {
                            Text(isExpired ? "Expired" : "Valid")
                                .foregroundStyle(isExpired ? .red : .green)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Value") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(cookie.value)
                            .font(NookDesign.Font.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: NookDesign.Size.textEditorHeight)
                }
            }
            .formStyle(.grouped)

            Divider()

            footerView
        }
        .frame(
            width: NookDesign.Size.sheetMediumWidth,
            height: NookDesign.Size.sheetMediumHeight
        )
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

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
        }
        .padding(NookDesign.Spacing.xl)
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
