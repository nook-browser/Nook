// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BasicAuthCredentialStore.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-06.
//

import Foundation

#if canImport(Security)
import Security
#endif

/// Simple persistence layer for HTTP basic-auth credentials keyed by protection space.
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

    /// Keychain account for a protection space inside one space's data store. Scheme, port and
    /// realm are part of it so a password saved for https is never sent to http or another port.
    /// A newline cannot appear in a host or a header value, so a realm cannot forge another
    /// origin's account. Entries from before this format are bare hosts and never match.
    static func account(for space: URLProtectionSpace, scope: UUID) -> String {
        let origin = "\(space.protocol ?? "")://\(space.host.lowercased()):\(space.port)"
        return [scope.uuidString, origin, space.realm ?? ""].joined(separator: "\n")
    }

    func credential(for account: String) -> StoredCredential? {
        guard !account.isEmpty else { return nil }

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
            _ = deleteCredential(for: account)
            return nil
        }
        #else
        return nil
        #endif
    }

    @discardableResult
    func saveCredential(_ credential: StoredCredential, for account: String) -> Bool {
        guard !account.isEmpty else { return false }

        #if canImport(Security)
        do {
            let data = try JSONEncoder().encode(Payload(username: credential.username, password: credential.password))

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
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
    func deleteCredential(for account: String) -> Bool {
        guard !account.isEmpty else { return false }

        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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
