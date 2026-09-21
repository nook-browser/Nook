// Licensed under GPL-3.0. See LICENSE.
//
//  AIKeychainStorage.swift
//  Nook
//
//  Keychain storage for AI provider API keys, plus the AIProviderConfig
//  conveniences that reach it. Runtime, not persisted config, so it stays in
//  the app rather than in NookSettings.
//

import Foundation
import NookSettings

#if canImport(Security)
import Security
#endif

/// Non-isolated Keychain storage for AI provider API keys
/// Uses internal synchronization for thread safety
final class AIKeychainStorage: @unchecked Sendable {
    static let shared = AIKeychainStorage()

    private let service = "com.nook.aiProvider"
    private let lock = NSLock()

    private init() {}

    func apiKey(for providerId: String) -> String? {
        guard !providerId.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }

        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    @discardableResult
    func saveAPIKey(_ apiKey: String, for providerId: String) -> Bool {
        guard !providerId.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        #if canImport(Security)
        guard let data = apiKey.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(insert as CFDictionary, nil)
        }

        return status == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    func deleteAPIKey(for providerId: String) -> Bool {
        guard !providerId.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }
}

// MARK: - AIProviderConfig

extension AIProviderConfig {
    /// Never encoded: the key lives in the Keychain under the provider's id.
    var apiKey: String {
        AIKeychainStorage.shared.apiKey(for: id) ?? ""
    }

    /// Same as the memberwise init, and it files the key in the Keychain on the way through.
    init(
        id: String = UUID().uuidString,
        displayName: String,
        providerType: AIProviderType,
        apiKey: String,
        baseURL: String? = nil,
        isEnabled: Bool = true,
        customHeaders: [String: String] = [:]
    ) {
        self.init(
            id: id,
            displayName: displayName,
            providerType: providerType,
            baseURL: baseURL,
            isEnabled: isEnabled,
            customHeaders: customHeaders
        )
        if !apiKey.isEmpty {
            AIKeychainStorage.shared.saveAPIKey(apiKey, for: id)
        }
    }
}
