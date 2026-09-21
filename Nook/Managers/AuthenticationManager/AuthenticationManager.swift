// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  AuthenticationManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/09/2025.
//

import AppKit
import CryptoKit
import Foundation
import Network
import WebKit
import NookBlocker
import NookWeb

@MainActor
final class AuthenticationManager: NSObject {
    private weak var browserManager: BrowserManager?
    private let credentialStore = BasicAuthCredentialStore()

    /// UserDefaults dictionary of accepted untrusted certificates: "host:port" to the leaf's SHA-256.
    private static let certificateExceptionsKey = "security.acceptedCertificateExceptions"
    /// Exceptions accepted in private windows; gone at quit.
    private var privateCertificateExceptions: [String: String] = [:]
    /// Connections waiting on a certificate alert that is already up, so one page load asks once.
    private var pendingCertificateDecisions: [String: [(Bool) -> Void]] = [:]

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for tab: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodDefault, NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            let space = challenge.protectionSpace

            // Without a host the prompt could only show text the server chose.
            guard !space.host.isEmpty else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return true
            }

            // An image or frame from another host must not raise a prompt over this page or
            // draw out a saved password. Rejecting the space lets the 401 stand without any
            // credential storage being consulted, which default handling would do. A proxy
            // is set by the system, not the page, and its host never matches.
            guard space.isProxy() || Self.isPageHost(space.host, of: tab) else {
                completionHandler(.rejectProtectionSpace, nil)
                return true
            }

            if challenge.previousFailureCount == 0,
               let account = credentialAccount(for: space, tab: tab),
               let stored = credentialStore.credential(for: account) {
                completionHandler(.useCredential, stored.asURLCredential)
                return true
            }

            presentBasicCredentialPrompt(for: challenge, tab: tab) { credential in
                if let credential {
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
            return true
        case NSURLAuthenticationMethodServerTrust:
            if let trust = challenge.protectionSpace.serverTrust {
                var error: CFError?
                if SecTrustEvaluateWithError(trust, &error) {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else if Self.isPrivateHost(challenge.protectionSpace.host) {
                    // Local network hosts (routers, NAS devices, IoT, etc.) are usually
                    // self-signed: accept once the user has confirmed this certificate
                    confirmUntrustedCertificate(trust, for: challenge.protectionSpace, tab: tab) { accepted in
                        if accepted {
                            completionHandler(.useCredential, URLCredential(trust: trust))
                        } else {
                            completionHandler(.cancelAuthenticationChallenge, nil)
                        }
                    }
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return true
        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.performDefaultHandling, nil)
            return true
        default:
            return false
        }
    }

    /// Returns true when the host is a private/local network address (RFC 1918, link-local, loopback).
    ///
    /// The host must be an address literal. Splitting on "." and dropping the components that
    /// are not numbers classified `10.0.0.1.attacker.example` as private, which handed a public
    /// host the self-signed certificate exception flow. `IPv4Address` parses strictly.
    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        // URLs carry IPv6 literals in brackets.
        let bare = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host

        if let v6 = IPv6Address(bare) {
            let bytes = Array(v6.rawValue)
            if v6.isLoopback { return true }                        // ::1
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }  // fe80::/10 link-local
            if (bytes[0] & 0xFE) == 0xFC { return true }            // fc00::/7 unique-local
            return false
        }

        guard let v4 = IPv4Address(bare) else { return false }
        let parts = Array(v4.rawValue)
        switch parts[0] {
        case 10: return true                                       // 10.0.0.0/8
        case 172: return (16...31).contains(parts[1])              // 172.16.0.0/12
        case 192: return parts[1] == 168                           // 192.168.0.0/16
        case 169: return parts[1] == 254                           // 169.254.0.0/16 link-local
        case 127: return true                                      // 127.0.0.0/8
        default: return false
        }
    }

    /// True when `host` serves the page in `tab`: the committed one, or the one a main-frame
    /// navigation is loading (the web view's url moves as soon as that starts).
    private static func isPageHost(_ host: String, of tab: PageSession) -> Bool {
        let host = host.lowercased()
        return tab.url.host?.lowercased() == host || tab.activeWebView.url?.host?.lowercased() == host
    }

    /// Keychain account for this challenge, or nil when nothing may be read or saved: private
    /// sessions leave no trace, and a proxy's password is never replayed without asking.
    private func credentialAccount(for space: URLProtectionSpace, tab: PageSession) -> String? {
        guard !tab.isPrivate, !space.isProxy(), let scope = tab.profile?.id else { return nil }
        return BasicAuthCredentialStore.account(for: space, scope: scope)
    }

    // MARK: - Untrusted Certificates

    /// Trust on first use: a certificate the user accepted for `host:port` is accepted again,
    /// anything else asks, and a certificate that replaced an accepted one says so.
    private func confirmUntrustedCertificate(
        _ trust: SecTrust,
        for space: URLProtectionSpace,
        tab: PageSession,
        completion: @escaping (Bool) -> Void
    ) {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return completion(false)
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02x", $0) }.joined()
        let key = "\(space.host.lowercased()):\(space.port)"
        let isPrivate = tab.isPrivate

        let persisted = UserDefaults.standard.dictionary(forKey: Self.certificateExceptionsKey) as? [String: String]
        let known = (isPrivate ? privateCertificateExceptions[key] : nil) ?? persisted?[key]
        if known == fingerprint { return completion(true) }

        // Same rule as credential prompts: no alert over a page for another host's resource.
        guard Self.isPageHost(space.host, of: tab) else { return completion(false) }

        let pendingKey = "\(key) \(fingerprint) \(isPrivate)"
        if pendingCertificateDecisions[pendingKey] != nil {
            pendingCertificateDecisions[pendingKey]?.append(completion)
            return
        }
        pendingCertificateDecisions[pendingKey] = [completion]

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The certificate for \(key) cannot be verified"
        alert.informativeText = known == nil
            ? "Nook cannot confirm that this is really \(space.host). Someone on your network could be answering in its place. Continue only if you expect this device to use a self-signed certificate."
            : "The certificate has CHANGED since it was last accepted. A reset or replaced device does that, and so does someone intercepting the connection."
        // Cancel first, so Return takes the safe choice.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return completion(false) }
            let accepted = response == .alertSecondButtonReturn
            if accepted, isPrivate {
                self.privateCertificateExceptions[key] = fingerprint
            } else if accepted {
                var exceptions = UserDefaults.standard.dictionary(forKey: Self.certificateExceptionsKey) as? [String: String] ?? [:]
                exceptions[key] = fingerprint
                UserDefaults.standard.set(exceptions, forKey: Self.certificateExceptionsKey)
            }
            self.pendingCertificateDecisions.removeValue(forKey: pendingKey)?.forEach { $0(accepted) }
        }

        if let window = tab.activeWebView.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    // MARK: - Basic Auth Prompt

    private func presentBasicCredentialPrompt(
        for challenge: URLAuthenticationChallenge,
        tab: PageSession,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let manager = browserManager else {
            completion(nil)
            return
        }

        let space = challenge.protectionSpace
        let host = space.host
        let scheme = space.protocol ?? "http"
        let isDefaultPort = space.port == 0 || (scheme == "http" && space.port == 80) || (scheme == "https" && space.port == 443)
        let displayHost = host.contains(":") ? "[\(host)]" : host
        let origin = "\(scheme)://\(displayHost)" + (isDefaultPort ? "" : ":\(space.port)")

        // The realm is the server's own text: drop control and bidi characters and keep it short.
        let unprintable = CharacterSet.controlCharacters.union(.newlines)
        let realmScalars = (space.realm ?? "").unicodeScalars.filter { !unprintable.contains($0) }
        let realm = String(String(String.UnicodeScalarView(realmScalars)).prefix(64))

        let account = credentialAccount(for: space, tab: tab)
        let prefilledCredential = account.flatMap { credentialStore.credential(for: $0) }
        let model = BasicAuthDialogModel(
            origin: origin,
            realm: realm,
            isProxy: space.isProxy(),
            isInsecure: scheme == "http" || !space.receivesCredentialSecurely,
            canRemember: account != nil,
            username: prefilledCredential?.username ?? "",
            password: prefilledCredential?.password ?? "",
            rememberCredential: prefilledCredential != nil
        )

        var didComplete = false
        func finish(with credential: URLCredential?) {
            guard didComplete == false else { return }
            didComplete = true
            completion(credential)
        }

        let dialog = BasicAuthDialog(
            model: model,
            onSubmit: { [weak self] username, password, remember in
                guard let self else { return }
                NSApp.mainWindow?.makeFirstResponder(nil)

                if let account {
                    if remember {
                        self.credentialStore.saveCredential(.init(username: username, password: password), for: account)
                    } else {
                        self.credentialStore.deleteCredential(for: account)
                    }
                    // Entries from before accounts carried scheme, port and realm were keyed
                    // by bare host. Nothing reads them any more; do not leave the secret behind.
                    self.credentialStore.deleteCredential(for: host)
                }

                manager.dialogManager.closeDialog()
                finish(with: URLCredential(user: username, password: password, persistence: .forSession))
            },
            onCancel: {
                NSApp.mainWindow?.makeFirstResponder(nil)
                manager.dialogManager.closeDialog()
                finish(with: nil)
            }
        )

        manager.dialogManager.showDialog(dialog)
    }
}
