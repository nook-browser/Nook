import Foundation
import WebKit
import UniformTypeIdentifiers
import os.log

final class MultiExtensionSchemeHandler: NSObject, WKURLSchemeHandler {
    private let logger = Logger(subsystem: "com.pulse.browser", category: "ExtensionSchemeHandler")
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            logger.error("Invalid URL in scheme handler request")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        logger.debug("Handling extension request: \(url.absoluteString)")
        
        // Handle CORS preflight OPTIONS requests
        if urlSchemeTask.request.httpMethod?.uppercased() == "OPTIONS" {
            handleOptionsRequest(urlSchemeTask, for: url)
            return
        }
        
        let extId = url.host ?? ""
        guard !extId.isEmpty else {
            logger.error("Empty extension ID in URL: \(url.absoluteString)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty extension ID"]))
            return
        }
        
        guard let mgr = BrowserWindowManager.shared.browserManager?.extensionManager else {
            logger.error("No ExtensionManager available")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -3, userInfo: [NSLocalizedDescriptionKey: "No ExtensionManager"]))
            return
        }
        
        guard let ext = mgr.installedExtensions.first(where: { $0.id == extId }) else {
            logger.error("Unknown extension ID: \(extId)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown extension id host"]))
            return
        }
        
        let baseDirectory = URL(fileURLWithPath: ext.packagePath).standardizedFileURL
        let relPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Enhanced path validation
        guard !relPath.isEmpty else {
            logger.error("Empty relative path in URL: \(url.absoluteString)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -5, userInfo: [NSLocalizedDescriptionKey: "Empty file path"]))
            return
        }
        
        // Enhanced security checks for malicious paths
        let forbiddenPatterns = [
            "../", "..\\", "..", "~", 
            "/etc/", "/usr/", "/var/", "/bin/", "/sbin/", "/sys/", "/proc/", "/dev/",
            "\\", ":", "*", "?", "\"", "<", ">", "|", // Windows reserved chars
            ".DS_Store", "Thumbs.db", ".git", ".svn", ".hg", // Hidden/system files
            "passwd", "shadow", "hosts", "resolv.conf" // System files
        ]
        
        let normalizedPath = relPath.lowercased()
        for pattern in forbiddenPatterns {
            if normalizedPath.contains(pattern.lowercased()) {
                logger.error("Potentially malicious path detected: \(relPath)")
                urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -6, userInfo: [NSLocalizedDescriptionKey: "Invalid file path"]))
                return
            }
        }
        
        // Additional check for null bytes and control characters
        if relPath.contains("\0") || relPath.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil {
            logger.error("Path contains invalid characters: \(relPath)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -6, userInfo: [NSLocalizedDescriptionKey: "Invalid file path characters"]))
            return
        }
        
        let targetURL = baseDirectory.appendingPathComponent(relPath).standardizedFileURL
        
        // Enhanced path traversal protection
        let basePath = baseDirectory.standardizedFileURL.path
        let targetPath = targetURL.path
        guard targetPath.hasPrefix(basePath) && targetPath != basePath else {
            logger.error("Path traversal blocked: \(targetPath) not within \(basePath)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -7, userInfo: [NSLocalizedDescriptionKey: "Path traversal blocked"]))
            return
        }
        
        // Additional file validation
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            logger.error("File does not exist: \(targetURL.path)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -8, userInfo: [NSLocalizedDescriptionKey: "File not found"]))
            return
        }
        
        // Check if it's a regular file (not a directory or special file)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            logger.error("Path is not a regular file: \(targetURL.path)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -9, userInfo: [NSLocalizedDescriptionKey: "Invalid file type"]))
            return
        }
        
        // Check file size to prevent loading extremely large files
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
            if let fileSize = fileAttributes[.size] as? Int64, fileSize > 100 * 1024 * 1024 { // 100MB limit
                logger.error("File too large: \(targetURL.path) (\(fileSize) bytes)")
                urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -10, userInfo: [NSLocalizedDescriptionKey: "File too large"]))
                return
            }
        } catch {
            logger.error("Failed to get file attributes for \(targetURL.path): \(error.localizedDescription)")
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -11, userInfo: [NSLocalizedDescriptionKey: "File access error"]))
            return
        }
        
        do {
            let data = try Data(contentsOf: targetURL)
            let mime = mimeType(for: targetURL)
            
            // Create response with proper CORS headers for extension origins
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: corsHeaders(for: url, mimeType: mime)
            ) ?? URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: textEncodingName(for: mime))
            
            logger.debug("Successfully serving file: \(targetURL.path) (\(data.count) bytes, \(mime))")
            
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch let error as NSError {
            logger.error("Failed to load file \(targetURL.path): \(error.localizedDescription) (code: \(error.code))")
            
            // Provide more specific error responses
            let errorCode: Int
            let errorMessage: String
            
            switch error.code {
            case NSFileReadNoPermissionError:
                errorCode = -12
                errorMessage = "Permission denied"
            case NSFileReadNoSuchFileError:
                errorCode = -13
                errorMessage = "File not found"
            case NSFileReadCorruptFileError:
                errorCode = -14
                errorMessage = "File corrupted"
            default:
                errorCode = -15
                errorMessage = "File read error"
            }
            
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to clean up for simple file serving
    }
    
    /// Handle CORS preflight OPTIONS requests
    private func handleOptionsRequest(_ urlSchemeTask: WKURLSchemeTask, for url: URL) {
        logger.debug("Handling OPTIONS request for: \(url.absoluteString)")
        
        let extensionId = url.host ?? ""
        let headers = [
            "Access-Control-Allow-Origin": "chrome-extension://\(extensionId)",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With, Accept, Accept-Language, Content-Language",
            "Access-Control-Max-Age": "86400",
            "Access-Control-Allow-Credentials": "true",
            "Content-Length": "0"
        ]
        
        if let response = HTTPURLResponse(
            url: url,
            statusCode: 204, // No Content
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data()) // Empty response body
            urlSchemeTask.didFinish()
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: "MultiExtensionSchemeHandler", code: -16, userInfo: [NSLocalizedDescriptionKey: "Failed to create OPTIONS response"]))
        }
    }
    
    /// Generate appropriate CORS headers for extension resources
    private func corsHeaders(for url: URL, mimeType: String) -> [String: String] {
        var headers = [String: String]()
        
        // Set MIME type
        headers["Content-Type"] = mimeType
        if let encoding = textEncodingName(for: mimeType) {
            headers["Content-Type"] = "\(mimeType); charset=\(encoding)"
        }
        
        // Enhanced extension origin CORS headers
        let extensionId = url.host ?? ""
        headers["Access-Control-Allow-Origin"] = "chrome-extension://\(extensionId)"
        headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
        headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Requested-With, Accept, Accept-Language, Content-Language"
        headers["Access-Control-Max-Age"] = "86400"
        headers["Access-Control-Allow-Credentials"] = "true"
        
        // Enhanced security headers
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "SAMEORIGIN"
        headers["X-XSS-Protection"] = "1; mode=block"
        headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        
        // Content Security Policy for executable content
        if mimeType == "text/html" {
            headers["Content-Security-Policy"] = "default-src 'self' chrome-extension://\(extensionId); script-src 'self' 'unsafe-inline' 'unsafe-eval' chrome-extension://\(extensionId); style-src 'self' 'unsafe-inline' chrome-extension://\(extensionId)"
        }
        
        // Enhanced cache control for different resource types
        if mimeType.hasPrefix("image/") || mimeType.hasPrefix("font/") {
            headers["Cache-Control"] = "public, max-age=31536000, immutable" // 1 year for static assets
        } else if mimeType == "application/javascript" || mimeType == "text/css" {
            headers["Cache-Control"] = "public, max-age=86400, must-revalidate" // 1 day for code
        } else if mimeType == "text/html" {
            headers["Cache-Control"] = "private, no-cache, no-store, must-revalidate" // No cache for HTML
        } else {
            headers["Cache-Control"] = "public, max-age=3600, must-revalidate" // 1 hour for other files
        }
        
        return headers
    }
    
    /// Enhanced MIME type detection with support for modern web formats
    private func mimeType(for url: URL) -> String {
        #if canImport(UniformTypeIdentifiers)
        if let utType = UTType(filenameExtension: url.pathExtension), let mime = utType.preferredMIMEType {
            return mime
        }
        #endif
        
        let ext = url.pathExtension.lowercased()
        switch ext {
        // Text formats
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "txt": return "text/plain"
        case "xml": return "text/xml"
        
        // JavaScript and related
        case "js": return "application/javascript"
        case "mjs": return "application/javascript"
        case "ts": return "application/typescript"
        case "jsx": return "application/javascript"
        case "tsx": return "application/typescript"
        case "vue": return "application/javascript"
        case "svelte": return "application/javascript"
        
        // Data formats
        case "json": return "application/json"
        case "jsonld": return "application/ld+json"
        case "xml": return "application/xml"
        case "yaml", "yml": return "application/x-yaml"
        case "toml": return "application/toml"
        case "csv": return "text/csv"
        case "tsv": return "text/tab-separated-values"
        
        // Images
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "avif": return "image/avif"
        
        // Fonts
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "eot": return "application/vnd.ms-fontobject"
        
        // Audio/Video
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "flac": return "audio/flac"
        case "aac": return "audio/aac"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        
        // Archives
        case "zip": return "application/zip"
        case "gz": return "application/gzip"
        case "tar": return "application/x-tar"
        
        // Documents
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        
        // Web Assembly and other modern formats
        case "wasm": return "application/wasm"
        case "map": return "application/json" // Source maps
        case "manifest": return "application/json" // Web app manifests
        case "webmanifest": return "application/manifest+json"
        
        // Default
        default: return "application/octet-stream"
        }
    }
    
    /// Determine text encoding for text-based MIME types
    private func textEncodingName(for mime: String) -> String? {
        if mime.hasPrefix("text/") || 
           mime == "application/javascript" || 
           mime == "application/typescript" ||
           mime == "application/json" ||
           mime == "application/xml" ||
           mime == "application/ld+json" ||
           mime == "application/x-yaml" ||
           mime == "image/svg+xml" {
            return "utf-8"
        }
        return nil
    }
}

