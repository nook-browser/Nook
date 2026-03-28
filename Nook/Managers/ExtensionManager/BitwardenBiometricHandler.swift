//
//  BitwardenBiometricHandler.swift
//  Nook
//
//  Handles Bitwarden's Safari extension biometric unlock protocol.
//  When Bitwarden's .appex calls connectNative("com.8bit.bitwarden"),
//  it expects the host app to handle Touch ID prompts and return
//  the user's symmetric key from the macOS Keychain.
//
//  Protocol (Safari mode — no encryption):
//    Extension sends: {command, userId, timestamp, messageId}
//    Host responds:   {message: {timestamp, messageId, response, [userKeyB64]}}
//

import Foundation
import LocalAuthentication
import os
import Security
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BitwardenBiometricHandler: InternalNativePortHandler {

    private static let logger = Logger(
        subsystem: "com.nook.browser",
        category: "BitwardenBiometric"
    )

    static let applicationIdentifiers = ["com.8bit.bitwarden"]

    // MARK: - Biometric status enum (matches Bitwarden's BiometricStatus)

    private enum BiometricStatus: Int {
        case available = 0
        case unlockNeeded = 1
        case hardwareUnavailable = 2
        case autoSetupNeeded = 3
        case manualSetupNeeded = 4
        case platformUnsupported = 5
        // 6 = DesktopDisconnected (not applicable — we ARE the host)
        // 7 = NotEnabledLocally
        // 8 = NotEnabledInConnectedDesktopApp
    }

    // MARK: - Keychain constants

    /// Bitwarden stores biometric keys under this Keychain service name.
    private static let keychainService = "Bitwarden_biometric"

    /// Account name pattern: "{userId}_user_biometric"
    private static func keychainAccount(for userId: String) -> String {
        "\(userId)_user_biometric"
    }

    // MARK: - InternalNativePortHandler

    func handleMessage(
        _ message: [String: Any],
        port: WKWebExtension.MessagePort
    ) -> Bool {
        guard let command = message["command"] as? String else { return false }

        let messageId = message["messageId"] as? Int ?? 0
        let userId = message["userId"] as? String ?? ""

        switch command {
        case "getBiometricsStatus":
            let status = checkBiometricAvailability()
            Self.logger.info("[Bitwarden] getBiometricsStatus -> \(status.rawValue)")
            sendResponse(port: port, messageId: messageId, response: status.rawValue)
            return true

        case "getBiometricsStatusForUser":
            let status = checkBiometricStatusForUser(userId: userId)
            Self.logger.info("[Bitwarden] getBiometricsStatusForUser(\(userId, privacy: .public)) -> \(status.rawValue)")
            sendResponse(port: port, messageId: messageId, response: status.rawValue)
            return true

        case "authenticateWithBiometrics":
            Self.logger.info("[Bitwarden] authenticateWithBiometrics")
            authenticateWithBiometrics { success in
                Self.logger.info("[Bitwarden] authenticateWithBiometrics -> \(success)")
                self.sendResponse(port: port, messageId: messageId, response: success)
            }
            return true

        case "unlockWithBiometricsForUser":
            Self.logger.info("[Bitwarden] unlockWithBiometricsForUser(\(userId, privacy: .public))")
            unlockWithBiometrics(userId: userId) { keyB64 in
                if let keyB64 {
                    Self.logger.info("[Bitwarden] unlockWithBiometricsForUser -> success (key length: \(keyB64.count))")
                    self.sendResponse(
                        port: port,
                        messageId: messageId,
                        response: true,
                        extraFields: ["userKeyB64": keyB64]
                    )
                } else {
                    Self.logger.info("[Bitwarden] unlockWithBiometricsForUser -> failed")
                    self.sendResponse(port: port, messageId: messageId, response: false)
                }
            }
            return true

        default:
            return false
        }
    }

    // MARK: - Biometric checks

    private func checkBiometricAvailability() -> BiometricStatus {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return .available
        }
        if let error {
            Self.logger.debug("[Bitwarden] Biometric evaluation error: \(error.localizedDescription, privacy: .public)")
            switch error.code {
            case LAError.biometryNotAvailable.rawValue:
                return .hardwareUnavailable
            case LAError.biometryNotEnrolled.rawValue:
                return .manualSetupNeeded
            case LAError.biometryLockout.rawValue:
                return .unlockNeeded
            default:
                return .hardwareUnavailable
            }
        }
        return .hardwareUnavailable
    }

    private func checkBiometricStatusForUser(userId: String) -> BiometricStatus {
        // First check hardware availability
        let hwStatus = checkBiometricAvailability()
        guard hwStatus == .available else { return hwStatus }

        // Check if a biometric key exists for this user
        let account = Self.keychainAccount(for: userId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecReturnData as String: false,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed:
            // Key exists (interaction not allowed means it exists but needs biometric)
            return .available
        case errSecItemNotFound:
            return .manualSetupNeeded
        default:
            Self.logger.debug("[Bitwarden] Keychain probe status: \(status)")
            return .manualSetupNeeded
        }
    }

    // MARK: - Biometric authentication

    private func authenticateWithBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedReason = "authenticate with Bitwarden"

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Bitwarden wants to verify your identity"
        ) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// Read the user's symmetric key from Keychain (triggers Touch ID).
    private func unlockWithBiometrics(userId: String, completion: @escaping (String?) -> Void) {
        let account = Self.keychainAccount(for: userId)

        // Perform Keychain access on a background thread since Touch ID blocks
        DispatchQueue.global(qos: .userInitiated).async {
            let context = LAContext()
            context.localizedReason = "unlock Bitwarden vault"

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            DispatchQueue.main.async {
                guard status == errSecSuccess, let data = result as? Data else {
                    if status != errSecSuccess {
                        Self.logger.error("[Bitwarden] Keychain read failed: \(status)")
                    }
                    completion(nil)
                    return
                }

                // The stored value may already be base64-encoded, or it may be raw bytes.
                // Bitwarden Desktop stores it as a base64 string in the Keychain.
                if let storedString = String(data: data, encoding: .utf8),
                   Self.isBase64(storedString)
                {
                    // Already base64-encoded
                    completion(storedString)
                } else {
                    // Raw bytes — encode to base64
                    completion(data.base64EncodedString())
                }
            }
        }
    }

    // MARK: - Response helpers

    private func sendResponse(
        port: WKWebExtension.MessagePort,
        messageId: Int,
        response: Any,
        extraFields: [String: Any] = [:]
    ) {
        var inner: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "messageId": messageId,
            "response": response,
        ]
        for (key, value) in extraFields {
            inner[key] = value
        }

        let envelope: [String: Any] = ["message": inner]
        port.sendMessage(envelope) { error in
            if let error {
                Self.logger.error("[Bitwarden] Failed to send response: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Utility

    private static func isBase64(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Quick heuristic: valid base64 chars only, reasonable length
        let base64Chars = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "+/="))
        return trimmed.rangeOfCharacter(from: base64Chars.inverted) == nil
            && trimmed.count >= 4
    }
}
