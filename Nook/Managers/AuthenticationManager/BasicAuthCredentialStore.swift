//
//  BasicAuthCredentialStore.swift
//  Nook
//
//  Created by Codex on 2025-09-06.
//

import Foundation

#if canImport(Security)
import Security
#endif

/// Simple persistence layer for HTTP basic-auth credentials keyed by host.
/// Uses the keychain to keep secrets off disk and available across launches.
@MainActor
final class BasicAuthCredentialStore {
    struct StoredCredential {
        let username: String
        let password: String
    }

    private enum KeychainError: Error {
        case unexpectedData
        case unhandled(OSStatus)
    }

    private let service = "com.nook.basicAuth"

    func credential(for host: String) -> StoredCredential? {
        guard !host.isEmpty else { return nil }

        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return StoredCredential(username: payload.username, password: payload.password)
        } catch {
            // If decoding fails, remove the corrupt record so future prompts can succeed.
            _ = deleteCredential(for: host)
            return nil
        }
        #else
        return nil
        #endif
    }

    @discardableResult
    func saveCredential(_ credential: StoredCredential, for host: String) -> Bool {
        guard !host.isEmpty else { return false }

        #if canImport(Security)
        do {
            let data = try JSONEncoder().encode(Payload(username: credential.username, password: credential.password))

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: host
            ]

            let attributes: [String: Any] = [kSecValueData as String: data]

            let status: OSStatus
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            } else {
                var insert = query
                insert[kSecValueData as String] = data
                status = SecItemAdd(insert as CFDictionary, nil)
            }

            guard status == errSecSuccess else { return false }
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    @discardableResult
    func deleteCredential(for host: String) -> Bool {
        guard !host.isEmpty else { return false }

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }
}

private struct Payload: Codable {
    let username: String
    let password: String
}

extension BasicAuthCredentialStore.StoredCredential {
    var asURLCredential: URLCredential {
        URLCredential(user: username, password: password, persistence: .forSession)
    }
}
