//
//  NativeMessagingHandler.swift
//  Nook
//
//  Native messaging support for browser extensions.
//  Handles launching host processes and communicating via stdin/stdout.
//

import Foundation
import os
import WebKit

// MARK: - Native Messaging Handler

@available(macOS 15.4, *)
class NativeMessagingHandler: NSObject {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "NativeMessaging")
    let applicationId: String
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private weak var port: WKWebExtension.MessagePort?
    private var outputBuffer = Data()

    init(applicationId: String) {
        self.applicationId = applicationId
        super.init()
    }

    func sendMessage(_ message: Any, completion: @escaping (Any?, Error?) -> Void) {
        // Single-shot message: Launch, write, read response, terminate
        launchProcess { [weak self] success in
            guard success, let self = self else {
                completion(nil, NSError(domain: "NativeMessaging", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch host"]))
                return
            }

            do {
                // Disable the readabilityHandler to avoid conflict with long-lived port mode
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil

                try self.writeMessage(message)

                // Read the response synchronously with a 5-second timeout
                let readHandle = self.outputPipe?.fileHandleForReading
                var responseData: Any?
                var readError: Error?
                let semaphore = DispatchSemaphore(value: 0)

                DispatchQueue.global(qos: .userInitiated).async {
                    defer { semaphore.signal() }
                    guard let handle = readHandle else {
                        readError = NSError(domain: "NativeMessaging", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output pipe"])
                        return
                    }

                    // Read 4-byte length prefix
                    let lengthData = handle.readData(ofLength: 4)
                    guard lengthData.count == 4 else {
                        readError = NSError(domain: "NativeMessaging", code: 4, userInfo: [NSLocalizedDescriptionKey: "Host closed without response"])
                        return
                    }

                    let length: UInt32 = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
                    let jsonData = handle.readData(ofLength: Int(length))

                    if let json = try? JSONSerialization.jsonObject(with: jsonData) {
                        responseData = json
                    } else {
                        readError = NSError(domain: "NativeMessaging", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse host response"])
                    }
                }

                let result = semaphore.wait(timeout: .now() + 5)
                self.terminateProcess()

                if result == .timedOut {
                    completion(nil, NSError(domain: "NativeMessaging", code: 6, userInfo: [NSLocalizedDescriptionKey: "Host response timed out"]))
                } else if let error = readError {
                    completion(nil, error)
                } else {
                    completion(responseData, nil)
                }
            } catch {
                self.terminateProcess()
                completion(nil, error)
            }
        }
    }

    func connect(port: WKWebExtension.MessagePort, hostAvailability: ((Bool) -> Void)? = nil) {
        self.port = port

        // Use closure-based handlers since delegate is not available
        port.messageHandler = { [weak self] (port, message) in
            do {
                try self?.writeMessage(message as Any)
            } catch {
                Self.logger.error("[NativeMessaging] Failed to write to host: \(error.localizedDescription, privacy: .public)")
            }
        }

        port.disconnectHandler = { [weak self] port in
            self?.terminateProcess()
        }

        launchProcess { [weak self] success in
            guard let self = self else { return }
            if !success {
                Self.logger.error("[NativeMessaging] Failed to launch host for \(self.applicationId)")
                DispatchQueue.main.async {
                    hostAvailability?(false)
                }
                port.disconnect()
            } else {
                DispatchQueue.main.async {
                    hostAvailability?(true)
                }
            }
        }
    }

    // MARK: - Process Management

    private func launchProcess(completion: @escaping (Bool) -> Void) {
        Self.logger.debug("Launching host for \(self.applicationId)...")

        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let manifestName = "\(self.applicationId).json"
            let browserDirs = [
                // Nook-specific (highest priority)
                "Library/Application Support/Nook/NativeMessagingHosts",
                // Chrome
                "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                // Chromium
                "Library/Application Support/Chromium/NativeMessagingHosts",
                // Microsoft Edge
                "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
                // Brave
                "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
                // Firefox / Mozilla
                "Library/Application Support/Mozilla/NativeMessagingHosts",
            ]
            var paths: [URL] = []
            for dir in browserDirs {
                // User-level
                paths.append(home.appendingPathComponent(dir).appendingPathComponent(manifestName))
                // System-level
                paths.append(URL(fileURLWithPath: "/\(dir)").appendingPathComponent(manifestName))
            }

            for path in paths {
                if let data = try? Data(contentsOf: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let binaryPath = json["path"] as? String {

                    Self.logger.info("Found manifest at \(path.path, privacy: .public)")

                    // SECURITY: Validate the binary path before launching
                    let binaryURL = URL(fileURLWithPath: binaryPath)
                    let fm = FileManager.default

                    // 1. Verify the binary path exists
                    guard fm.fileExists(atPath: binaryPath) else {
                        Self.logger.error("[NativeMessaging] SECURITY: Binary path does not exist: \(binaryPath, privacy: .public)")
                        continue
                    }

                    // 2. Resolve symlinks and verify the canonical path matches expected locations
                    let canonicalURL = binaryURL.resolvingSymlinksInPath()
                    let canonicalPath = canonicalURL.path
                    if canonicalPath != binaryPath {
                        Self.logger.warning("[NativeMessaging] SECURITY: Binary path is a symlink: \(binaryPath, privacy: .public) -> \(canonicalPath, privacy: .public)")
                    }

                    // 3. Verify the binary is in an expected directory
                    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                    let allowedPrefixes = [
                        "\(homeDir)/Library/",
                        "/Applications/",
                        "/usr/local/",
                        "/usr/bin/",
                        "/opt/",
                        "/Library/"
                    ]
                    let isInExpectedLocation = allowedPrefixes.contains { prefix in
                        canonicalPath.hasPrefix(prefix)
                    }
                    if !isInExpectedLocation {
                        Self.logger.error("[NativeMessaging] SECURITY: Refusing to launch binary in an unexpected location: \(canonicalPath, privacy: .public)")
                        continue
                    }

                    // 4. Verify the binary path doesn't contain path traversal
                    if binaryPath.contains("..") {
                        Self.logger.error("[NativeMessaging] SECURITY: Path traversal detected in binary path: \(binaryPath, privacy: .public)")
                        continue
                    }

                    Self.logger.info("[NativeMessaging] Launching binary: \(canonicalPath, privacy: .public) (original: \(binaryPath, privacy: .public))")

                    // Launch it
                    let process = Process()
                    process.executableURL = canonicalURL

                    let input = Pipe()
                    let output = Pipe()
                    let error = Pipe()

                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = error

                    self.inputPipe = input
                    self.outputPipe = output
                    self.errorPipe = error
                    self.process = process

                    // Handle stdout (messages from host)
                    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            self?.handleOutput(data)
                        }
                    }

                    do {
                        try process.run()
                        Self.logger.debug("   🚀 Process launched!")
                        completion(true)
                        return
                    } catch {
                        Self.logger.error("Failed to launch process: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            Self.logger.debug("   ⚠️ No manifest found for \(self.applicationId)")
            completion(false)
        }
    }

    private func terminateProcess() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func writeMessage(_ message: Any) throws {
        guard let input = inputPipe else {
            throw NSError(domain: "NativeMessaging", code: 2, userInfo: [NSLocalizedDescriptionKey: "No input pipe available — host process not running"])
        }

        let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
        var length = UInt32(jsonData.count)

        // Native messaging protocol: 4 bytes length (native byte order) + JSON
        let lengthData = Data(bytes: &length, count: 4)

        try input.fileHandleForWriting.write(contentsOf: lengthData)
        try input.fileHandleForWriting.write(contentsOf: jsonData)
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        // Process all complete messages in the buffer
        while outputBuffer.count >= 4 {
            // Read 4-byte length prefix (native byte order)
            let length: UInt32 = outputBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }
            let totalNeeded = 4 + Int(length)

            guard outputBuffer.count >= totalNeeded else {
                // Wait for more data
                break
            }

            let jsonData = outputBuffer.subdata(in: 4..<totalNeeded)
            outputBuffer.removeSubrange(0..<totalNeeded)

            if let json = try? JSONSerialization.jsonObject(with: jsonData) {
                Self.logger.debug("Received from host: \(String(describing: json))")
                port?.sendMessage(json) { _ in }
            } else {
                Self.logger.error("Failed to parse JSON from host (\(jsonData.count) bytes)")
            }
        }
    }
}
