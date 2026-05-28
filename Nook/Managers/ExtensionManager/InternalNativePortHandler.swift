//
//  InternalNativePortHandler.swift
//  Nook
//
//  Protocol for handling native messaging ports internally when no external
//  host process is available. Safari extensions (.appex) expect the host app
//  to respond on these channels.
//

import Foundation
import WebKit

/// A handler for native messaging commands received on a port.
/// Implementations are extension-specific (e.g. Bitwarden biometric unlock).
@available(macOS 15.5, *)
@MainActor
protocol InternalNativePortHandler: AnyObject {
    /// The native messaging application identifiers this handler supports.
    /// e.g. ["com.8bit.bitwarden"] for Bitwarden biometric port.
    static var applicationIdentifiers: [String] { get }

    /// Handle an incoming message on the port.
    /// Return `true` if the message was handled, `false` to fall through to generic handling.
    func handleMessage(
        _ message: [String: Any],
        port: WKWebExtension.MessagePort
    ) -> Bool
}
