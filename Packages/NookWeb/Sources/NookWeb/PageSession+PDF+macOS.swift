// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+PDF+macOS.swift
//  NookWeb
//
//  WebKit shows a PDF in its own viewer. Nook turns that viewer's HUD off (see
//  `BrowserConfiguration.hidePDFHUD`) and draws glass controls instead; these are what they call.
//  Every private selector here is checked with `responds(to:)`, so a WebKit that drops one
//  leaves that control doing nothing rather than crashing.
//

#if os(macOS)
import AppKit
import WebKit

extension WKWebView {
    /// The main resource's original bytes, the PDF file itself rather than a re-rendering of it.
    func nookMainResourceData() async -> Data? {
        let selector = NSSelectorFromString("_getMainResourceDataWithCompletionHandler:")
        guard responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, @escaping @convention(block) (NSData?, NSError?) -> Void) -> Void
        let call = unsafeBitCast(method(for: selector), to: Getter.self)
        return await withCheckedContinuation { continuation in
            call(self, selector) { data, _ in continuation.resume(returning: data as Data?) }
        }
    }
}

extension PageSession {
    /// WebKit's own bar calls this for Save. It is off, so this is the fallback for a WebKit that
    /// ignores the switch; without it that Save button does nothing and logs nothing.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(_ webView: WKWebView, saveDataToFile data: Data, suggestedFilename: String, mimeType: String, originatingURL: URL) {
        controller?.sessionDelegate?.saveFile(data, suggestedFilename: suggestedFilename, originalURL: originatingURL, from: webView)
    }

    /// Saves the PDF into Downloads as a finished download.
    public func savePDF(from webView: WKWebView) {
        Task { @MainActor in
            guard let data = await webView.nookMainResourceData(), !data.isEmpty else { return }
            controller?.sessionDelegate?.saveFile(data, suggestedFilename: pdfFilename, originalURL: url, from: webView)
        }
    }

    /// Hands the PDF to the default PDF app, the way the viewer's own button did: written to a
    /// fresh temporary folder, read-only, then opened.
    public func openPDFInDefaultApp(from webView: WKWebView) {
        Task { @MainActor in
            guard let data = await webView.nookMainResourceData(), !data.isEmpty else { return }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookPDFs", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let file = folder.appendingPathComponent(pdfFilename)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
            } catch {
                return
            }
            NSWorkspace.shared.open(file)
        }
    }

    /// The URL's last component, which is how the file is named on the server, with `.pdf` added
    /// when the URL did not carry it (`/download?id=123`).
    var pdfFilename: String {
        var name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        name = name.replacingOccurrences(of: "/", with: "_")
        if name.isEmpty || name == "/" { name = url.host ?? "document" }
        if (name as NSString).pathExtension.lowercased() != "pdf" { name += ".pdf" }
        return name
    }
}
#endif
