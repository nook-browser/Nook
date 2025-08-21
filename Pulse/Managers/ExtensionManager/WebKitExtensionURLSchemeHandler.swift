//
//  WebKitExtensionURLSchemeHandler.swift
//  Pulse
//
//  Custom URL scheme handler for webkit-extension:// URLs
//  Maps extension URLs to actual file system paths and serves content with proper MIME types
//
//  USAGE:
//  The handler is automatically registered in BrowserConfiguration for the "webkit-extension" scheme.
//  It handles URLs in the format: webkit-extension://<extension-uuid>/<path>
//
//  EXAMPLES:
//  webkit-extension://115d7349-3e91-424d-9138-16b1f3419145/popup.html
//  webkit-extension://115d7349-3e91-424d-9138-16b1f3419145/css/popup.css
//  webkit-extension://115d7349-3e91-424d-9138-16b1f3419145/js/popup.js
//
//  TESTING:
//  Use ExtensionManager.shared.testWebKitExtensionURLSchemeHandler() to test the implementation
//

import Foundation
import WebKit
import UniformTypeIdentifiers

@available(macOS 15.4, *)
class WebKitExtensionURLSchemeHandler: NSObject, WKURLSchemeHandler {
    
    // MARK: - Properties
    
    private let extensionsBasePath: String
    
    // MARK: - MIME Type Mapping
    
    private let mimeTypeMap: [String: String] = [
        "html": "text/html",
        "htm": "text/html",
        "css": "text/css",
        "js": "application/javascript",
        "json": "application/json",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "txt": "text/plain",
        "xml": "application/xml"
    ]
    
    // MARK: - Initialization
    
    init(extensionsBasePath: String = "/Users/jonathancaudill/Library/Containers/baginskimaciej.Pulse/Data/Library/Application Support/Pulse/Extensions") {
        self.extensionsBasePath = extensionsBasePath
        super.init()
        print("WebKitExtensionURLSchemeHandler: Initialized with base path: \(extensionsBasePath)")
    }
    
    // MARK: - WKURLSchemeHandler Implementation
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            print("WebKitExtensionURLSchemeHandler: Invalid URL in request")
            completeTaskWithError(urlSchemeTask, error: URLError(.badURL))
            return
        }
        
        print("WebKitExtensionURLSchemeHandler: Handling request for URL: \(url.absoluteString)")
        
        // Validate webkit-extension scheme
        guard url.scheme == "webkit-extension" else {
            print("WebKitExtensionURLSchemeHandler: Invalid scheme: \(url.scheme ?? "none")")
            completeTaskWithError(urlSchemeTask, error: URLError(.unsupportedURL))
            return
        }
        
        // Extract extension UUID from host
        guard let extensionUUID = url.host, !extensionUUID.isEmpty else {
            print("WebKitExtensionURLSchemeHandler: Missing or empty extension UUID in host")
            completeTaskWithError(urlSchemeTask, error: URLError(.badURL))
            return
        }
        
        // Validate UUID format
        guard UUID(uuidString: extensionUUID) != nil else {
            print("WebKitExtensionURLSchemeHandler: Invalid UUID format: \(extensionUUID)")
            completeTaskWithError(urlSchemeTask, error: URLError(.badURL))
            return
        }
        
        // Build file path
        let filePath = buildFilePath(for: url, extensionUUID: extensionUUID)
        
        print("WebKitExtensionURLSchemeHandler: Attempting to serve file at path: \(filePath)")
        
        // Serve the file
        serveFile(at: filePath, for: urlSchemeTask, originalURL: url)
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Task has been cancelled - nothing to clean up in this implementation
        print("WebKitExtensionURLSchemeHandler: Task cancelled for URL: \(urlSchemeTask.request.url?.absoluteString ?? "unknown")")
    }
    
    // MARK: - Private Methods
    
    private func buildFilePath(for url: URL, extensionUUID: String) -> String {
        // Start with extension directory
        var pathComponents = [extensionsBasePath, extensionUUID]
        
        // Add URL path components
        let urlPath = url.path
        if !urlPath.isEmpty && urlPath != "/" {
            // Remove leading slash and split path
            let cleanPath = urlPath.hasPrefix("/") ? String(urlPath.dropFirst()) : urlPath
            if !cleanPath.isEmpty {
                pathComponents.append(cleanPath)
            }
        }
        
        // If no specific file requested, default to index.html
        let fullPath = pathComponents.joined(separator: "/")
        
        // Check if path points to a directory and default to index.html
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue {
            return fullPath + "/index.html"
        }
        
        return fullPath
    }
    
    private func serveFile(at filePath: String, for task: WKURLSchemeTask, originalURL: URL) {
        // Security check: Ensure the file path is within the extensions directory
        let canonicalFilePath = (filePath as NSString).standardizingPath
        let canonicalBasePath = (extensionsBasePath as NSString).standardizingPath
        
        guard canonicalFilePath.hasPrefix(canonicalBasePath) else {
            print("WebKitExtensionURLSchemeHandler: Security violation - path outside extensions directory: \(canonicalFilePath)")
            completeTaskWithError(task, error: URLError(.fileDoesNotExist))
            return
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: canonicalFilePath) else {
            print("WebKitExtensionURLSchemeHandler: File not found: \(canonicalFilePath)")
            completeTaskWithError(task, error: URLError(.fileDoesNotExist))
            return
        }
        
        // Read file content
        do {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: canonicalFilePath))
            
            // Determine MIME type
            let mimeType = getMimeType(for: canonicalFilePath)
            
            // Create response
            let response = URLResponse(
                url: originalURL,
                mimeType: mimeType,
                expectedContentLength: fileData.count,
                textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
            )
            
            print("WebKitExtensionURLSchemeHandler: Serving file with MIME type: \(mimeType), size: \(fileData.count) bytes")
            
            // Send response
            task.didReceive(response)
            task.didReceive(fileData)
            task.didFinish()
            
        } catch {
            print("WebKitExtensionURLSchemeHandler: Error reading file at \(canonicalFilePath): \(error)")
            completeTaskWithError(task, error: error)
        }
    }
    
    private func getMimeType(for filePath: String) -> String {
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        
        // Check our predefined MIME types first
        if let mimeType = mimeTypeMap[fileExtension] {
            return mimeType
        }
        
        // Fall back to system MIME type detection
        if #available(macOS 11.0, *) {
            if let utType = UTType(filenameExtension: fileExtension),
               let mimeType = utType.preferredMIMEType {
                return mimeType
            }
        }
        
        // Default fallback
        if fileExtension.isEmpty {
            return "text/html" // Default for extensionless files (likely HTML)
        } else {
            return "application/octet-stream" // Binary fallback
        }
    }
    
    private func completeTaskWithError(_ task: WKURLSchemeTask, error: Error) {
        print("WebKitExtensionURLSchemeHandler: Completing task with error: \(error)")
        
        // Convert error to NSError if needed for WKURLSchemeTask
        let nsError = error as NSError
        task.didFailWithError(nsError)
    }
}

// MARK: - URLError Extension for Custom Errors

extension URLError {
    static let unsupportedURL = URLError(.unsupportedURL)
    static let badURL = URLError(.badURL)
    static let fileDoesNotExist = URLError(.fileDoesNotExist)
}