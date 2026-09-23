// Licensed under GPL-3.0. See LICENSE.
//
//  WKWebView+Print+macOS.swift
//  NookWeb
//
//  One print path for Cmd+P, the File menu, the PDF controls and a page's own window.print().
//  `printOperation(with:)` prints a PDF's own pages as well as a web page, and needs no frame
//  workaround: both measured on macOS 27 by printing to a file and reading the text back.
//

#if os(macOS)
import AppKit
import WebKit

extension WKWebView {
    /// The print panel as a sheet on this web view's window. `frame` is the frame handle WebKit
    /// passes when a subframe calls print(), so only that frame prints. Nothing happens while the
    /// window already has a sheet, or when the page is not in a window (a background tab).
    public func nookPrint(frame: AnyObject? = nil, completion: @escaping () -> Void = {}) {
        guard let window, window.attachedSheet == nil else {
            completion()
            return
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        let operation = frame.flatMap { printOperation(with: info, forFrame: $0) } ?? printOperation(with: info)
        let finish = PrintCompletion(completion)
        PrintCompletion.running.insert(finish)
        operation.runModal(for: window, delegate: finish, didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    /// `_printOperationWithPrintInfo:forFrame:`, private; nil when WebKit no longer has it.
    private func printOperation(with info: NSPrintInfo, forFrame frame: AnyObject) -> NSPrintOperation? {
        let selector = NSSelectorFromString("_printOperationWithPrintInfo:forFrame:")
        guard responds(to: selector) else { return nil }
        typealias Call = @convention(c) (AnyObject, Selector, NSPrintInfo, AnyObject) -> NSPrintOperation?
        return unsafeBitCast(method(for: selector), to: Call.self)(self, selector, info, frame)
    }
}

/// Runs the caller's completion once the print sheet ends. NSPrintOperation does not retain its
/// delegate, so `running` does until then.
@MainActor
private final class PrintCompletion: NSObject {
    static var running = Set<PrintCompletion>()
    private let done: () -> Void

    init(_ done: @escaping () -> Void) {
        self.done = done
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        done()
        Self.running.remove(self)
    }
}

extension PageSession {
    /// A page's own window.print(). Without this WebKit gets no answer and the call does nothing.
    /// The page waits on `completionHandler`, so it cannot close or rewrite itself mid-print.
    @objc(_webView:printFrame:pdfFirstPageSize:completionHandler:)
    func webView(_ webView: WKWebView, printFrame frame: AnyObject, pdfFirstPageSize: CGSize, completionHandler: @escaping () -> Void) {
        webView.nookPrint(frame: frame, completion: completionHandler)
    }
}
#endif
