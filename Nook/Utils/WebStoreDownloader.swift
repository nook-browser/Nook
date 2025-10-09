//
//  WebStoreDownloader.swift
//  Nook
//
//  Chrome Web Store extension downloader
//

import Foundation
import AppKit

@MainActor
struct WebStoreDownloader {
    
    /// Download extension from Chrome Web Store
    static func downloadExtension(extensionId: String, completionHandler: @escaping (Result<URL, Error>) -> Void) {
        // Simulate Chrome version for API compatibility
        let chromeVersion = "120.0.6099.129"
        let naclArch = getNaclArch()
        
        // Build Chrome Web Store API URL
        let urlString = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=\(chromeVersion)&x=id%3D\(extensionId)%26installsource%3Dondemand%26uc&nacl_arch=\(naclArch)&acceptformat=crx2,crx3"
        
        guard let url = URL(string: urlString) else {
            completionHandler(.failure(WebStoreError.invalidURL))
            return
        }
        
        // Download CRX file
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            Task { @MainActor in
                if let error = error {
                    completionHandler(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completionHandler(.failure(WebStoreError.noData))
                    return
                }
                
                // Convert CRX to ZIP by stripping header
                guard let zipData = convertCRXtoZIP(data) else {
                    completionHandler(.failure(WebStoreError.conversionFailed))
                    return
                }
                
                // Save to temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(extensionId).zip")
                
                do {
                    try zipData.write(to: tempFile)
                    completionHandler(.success(tempFile))
                } catch {
                    completionHandler(.failure(error))
                }
            }
        }
        
        task.resume()
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
            // CRX2 format
            let publicKeyLength = Int(bytes[8]) + (Int(bytes[9]) << 8) + (Int(bytes[10]) << 16) + (Int(bytes[11]) << 24)
            let signatureLength = Int(bytes[12]) + (Int(bytes[13]) << 8) + (Int(bytes[14]) << 16) + (Int(bytes[15]) << 24)
            zipStartOffset = 16 + publicKeyLength + signatureLength
        } else if version == 3 {
            // CRX3 format - more complex header
            let headerSize = Int(bytes[8]) + (Int(bytes[9]) << 8) + (Int(bytes[10]) << 16) + (Int(bytes[11]) << 24)
            zipStartOffset = 12 + headerSize
        } else {
            return nil
        }
        
        guard zipStartOffset < crxData.count else {
            return nil
        }
        
        // Extract ZIP data
        return crxData.subdata(in: zipStartOffset..<crxData.count)
    }
    
    /// Get CPU architecture string for Chrome API
    private static func getNaclArch() -> String {
        #if arch(arm64)
        return "arm"
        #elseif arch(x86_64)
        return "x86-64"
        #else
        return "x86-32"
        #endif
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
            return "Invalid Chrome Web Store URL"
        case .noData:
            return "No data received from Chrome Web Store"
        case .conversionFailed:
            return "Failed to convert CRX to ZIP format"
        case .invalidCRX:
            return "Invalid CRX file format"
        }
    }
}

