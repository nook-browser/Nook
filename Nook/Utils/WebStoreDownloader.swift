// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  WebStoreDownloader.swift
//  Nook
//
//  Chrome Web Store and Edge Add-ons extension downloader
//

import Foundation

enum ExtensionStore: String {
    case chrome
    case edge

    /// Store extension IDs are 32 characters in the range a-p.
    static func isValidExtensionID(_ id: String) -> Bool {
        id.count == 32 && id.utf8.allSatisfy { $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "p") }
    }

    /// Update-protocol endpoint. `response=redirect` serves the CRX, `response=updatecheck` serves XML.
    func updateServiceURL(response: String, extensionId: String, version: String?, prodVersion: String) -> URL? {
        let base: String
        switch self {
        case .chrome: base = "https://clients2.google.com/service/update2/crx"
        case .edge: base = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
        }
        // Every interpolated value is a-p, digits, or dots, so no further escaping is needed.
        guard Self.isValidExtensionID(extensionId),
              ([version, prodVersion].compactMap { $0 }).allSatisfy({ $0.allSatisfy { $0.isNumber || $0 == "." } })
        else { return nil }
        var x = "id%3D\(extensionId)"
        if let version { x += "%26v%3D\(version)" } else { x += "%26installsource%3Dondemand" }
        x += "%26uc"
        return URL(string: "\(base)?response=\(response)&prodversion=\(prodVersion)&acceptformat=crx3&x=\(x)")
    }
}

@MainActor
struct WebStoreDownloader {

    static let fallbackChromeVersion = "141.0.7390.78"

    /// Download the current CRX for `extensionId` and return a temporary ZIP file.
    static func downloadExtension(
        extensionId: String,
        store: ExtensionStore = .chrome,
        completionHandler: @escaping (Result<URL, Error>) -> Void
    ) {
        guard ExtensionStore.isValidExtensionID(extensionId) else {
            completionHandler(.failure(WebStoreError.invalidURL))
            return
        }
        Task {
            let prodVersion = await latestChromeVersion()
            guard let url = store.updateServiceURL(
                response: "redirect", extensionId: extensionId, version: nil, prodVersion: prodVersion
            ) else {
                completionHandler(.failure(WebStoreError.invalidURL))
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw WebStoreError.noData
                }
                guard let zipData = convertCRXtoZIP(data) else {
                    throw WebStoreError.conversionFailed
                }
                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(extensionId)-\(UUID().uuidString).zip")
                try zipData.write(to: tempFile)
                completionHandler(.success(tempFile))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    /// Ask the store whether a version newer than `currentVersion` exists. Returns the new version or nil.
    static func availableUpdate(
        extensionId: String,
        store: ExtensionStore,
        currentVersion: String
    ) async -> String? {
        let prodVersion = await latestChromeVersion()
        guard let url = store.updateServiceURL(
            response: "updatecheck", extensionId: extensionId, version: currentVersion, prodVersion: prodVersion
        ),
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let xml = String(data: data, encoding: .utf8)
        else { return nil }

        // <updatecheck codebase="..." version="1.2.3" status="ok"/> or status="noupdate"
        guard let tagRange = xml.range(of: "<updatecheck[^>]*>", options: .regularExpression) else { return nil }
        let tag = String(xml[tagRange])
        guard tag.contains("status=\"ok\""),
              let versionRange = tag.range(of: "version=\"[0-9.]+\"", options: .regularExpression)
        else { return nil }
        let version = String(tag[versionRange].dropFirst(9).dropLast())
        return isVersion(version, newerThan: currentVersion) ? version : nil
    }

    /// Chrome version strings are up to four dot-separated integers.
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static var cachedChromeVersion: String?

    /// The update server filters by browser version, so report a current stable Chrome.
    private static func latestChromeVersion() async -> String {
        if let cachedChromeVersion { return cachedChromeVersion }
        guard let url = URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let version = (try? JSONDecoder().decode(ChromeVersionResponse.self, from: data))?.versions.first?.version
        else { return fallbackChromeVersion }
        cachedChromeVersion = version
        return version
    }

    /// Convert CRX file to ZIP by stripping the CRX header
    private static func convertCRXtoZIP(_ crxData: Data) -> Data? {
        guard crxData.count > 16 else { return nil }

        let bytes = [UInt8](crxData)

        // Check magic number (Cr24)
        guard bytes[0] == 0x43, bytes[1] == 0x72, bytes[2] == 0x32, bytes[3] == 0x34 else {
            return nil
        }

        let version = bytes[4]
        let zipStartOffset: Int

        if version == 2 {
            let publicKeyLength = Int(bytes[8]) + (Int(bytes[9]) << 8) + (Int(bytes[10]) << 16) + (Int(bytes[11]) << 24)
            let signatureLength = Int(bytes[12]) + (Int(bytes[13]) << 8) + (Int(bytes[14]) << 16) + (Int(bytes[15]) << 24)
            zipStartOffset = 16 + publicKeyLength + signatureLength
        } else if version == 3 {
            let headerSize = Int(bytes[8]) + (Int(bytes[9]) << 8) + (Int(bytes[10]) << 16) + (Int(bytes[11]) << 24)
            zipStartOffset = 12 + headerSize
        } else {
            return nil
        }

        guard zipStartOffset < crxData.count else {
            return nil
        }

        // ponytail: CRX signature is not verified; integrity rests on HTTPS to the store's update host.
        return crxData.subdata(in: zipStartOffset..<crxData.count)
    }
}

enum WebStoreError: LocalizedError {
    case invalidURL
    case noData
    case conversionFailed
    case invalidCRX

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid extension store URL or extension ID"
        case .noData:
            return "The extension store did not return the extension"
        case .conversionFailed:
            return "Failed to convert CRX to ZIP format"
        case .invalidCRX:
            return "Invalid CRX file format"
        }
    }
}

// MARK: - Chrome Version API Response Models

struct ChromeVersionResponse: Codable {
    let versions: [ChromeVersion]
}

struct ChromeVersion: Codable {
    let name: String
    let version: String
}
