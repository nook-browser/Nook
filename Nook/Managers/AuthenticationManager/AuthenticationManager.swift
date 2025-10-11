//
//  AuthenticationManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/09/2025.
//

import AppKit
import Foundation
import WebKit

@MainActor
final class AuthenticationManager: NSObject {
    struct IdentityRequest {
        let requestId: String
        let url: URL
        let interactive: Bool
        let prefersEphemeralSession: Bool
        let explicitCallbackScheme: String?
    }

    enum IdentityFlowResult {
        case success(URL)
        case cancelled
        case failure(IdentityFailure)
    }

    enum IdentityFailure: Equatable {
        case interactionRequired
        case missingCallbackHandler
        case unableToStart
        case fallbackUnavailable
        case fallbackCancelled
        case underlying(String)

        var code: String {
            switch self {
            case .interactionRequired:
                return "interaction_required"
            case .missingCallbackHandler:
                return "missing_callback_handler"
            case .unableToStart:
                return "unable_to_start"
            case .fallbackUnavailable:
                return "fallback_unavailable"
            case .fallbackCancelled:
                return "fallback_cancelled"
            case .underlying:
                return "error"
            }
        }

        var message: String {
            switch self {
            case .interactionRequired:
                return "User interaction is required to complete this authentication flow."
            case .missingCallbackHandler:
                return "Could not determine an appropriate callback handler for this authentication flow."
            case .unableToStart:
                return "The authentication session could not be started."
            case .fallbackUnavailable:
                return "Unable to present a fallback authentication window."
            case .fallbackCancelled:
                return "Authentication window was closed before completion."
            case let .underlying(details):
                return details
            }
        }
    }

    private weak var browserManager: BrowserManager?
    private let credentialStore = BasicAuthCredentialStore()
    private var activeIdentityRequest: IdentityRequest?
    private weak var activeIdentityTab: Tab?
    private var waitingForMiniWindow = false
    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func beginIdentityFlow(_ request: IdentityRequest, from tab: Tab) {
        // Non-interactive flows cannot be satisfied without UI today.
        if request.interactive == false {
            tab.finishIdentityFlow(requestId: request.requestId, with: .failure(.interactionRequired))
            return
        }

        browserManager?.trackingProtectionManager.disableTemporarily(for: tab, duration: 15 * 60)

        cancelActiveIdentityFlow()

        guard let manager = browserManager else {
            tab.finishIdentityFlow(requestId: request.requestId, with: .failure(.fallbackUnavailable))
            return
        }

        activeIdentityRequest = request
        activeIdentityTab = tab
        waitingForMiniWindow = true

        manager.externalMiniWindowManager.present(url: request.url) { [weak self] success, finalURL in
            guard let self else { return }
            Task { @MainActor in
                self.handleMiniWindowCompletion(success: success, finalURL: finalURL)
            }
        }
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for tab: Tab,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodDefault, NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            let host = challenge.protectionSpace.host

            if !host.isEmpty,
               challenge.previousFailureCount == 0,
               let stored = credentialStore.credential(for: host) {
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

    private func handleMiniWindowCompletion(success: Bool, finalURL: URL?) {
        guard let request = activeIdentityRequest, let tab = activeIdentityTab else {
            clearActiveIdentityState()
            return
        }

        waitingForMiniWindow = false
        defer { clearActiveIdentityState() }

        guard success, let url = finalURL else {
            tab.finishIdentityFlow(requestId: request.requestId, with: .failure(.fallbackCancelled))
            return
        }

        tab.finishIdentityFlow(requestId: request.requestId, with: .success(url))
        tab.activeWebView.reload()
    }

    private func cancelActiveIdentityFlow() {
        if let request = activeIdentityRequest, let tab = activeIdentityTab {
            tab.finishIdentityFlow(requestId: request.requestId, with: .cancelled)
        }
        clearActiveIdentityState()
    }

    private func clearActiveIdentityState() {
        activeIdentityRequest = nil
        activeIdentityTab = nil
        waitingForMiniWindow = false
    }

    private func presentBasicCredentialPrompt(
        for challenge: URLAuthenticationChallenge,
        tab: Tab,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let manager = browserManager else {
            completion(nil)
            return
        }

        let host = challenge.protectionSpace.host
        let displayHost: String
        if !host.isEmpty {
            displayHost = host
        } else if let realm = challenge.protectionSpace.realm, !realm.isEmpty {
            displayHost = realm
        } else if let url = tab.activeWebView.url {
            displayHost = url.host ?? url.absoluteString
        } else {
            displayHost = "this site"
        }

        let prefilledCredential = !host.isEmpty ? credentialStore.credential(for: host) : nil
        let model = BasicAuthDialogModel(
            host: displayHost,
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

                if !host.isEmpty {
                    if remember {
                        self.credentialStore.saveCredential(.init(username: username, password: password), for: host)
                    } else {
                        self.credentialStore.deleteCredential(for: host)
                    }
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
