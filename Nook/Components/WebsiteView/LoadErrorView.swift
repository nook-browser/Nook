// Licensed under GPL-3.0. See LICENSE.
//
//  LoadErrorView.swift
//  Nook
//
//  The page shown when a load fails before anything commits. Native buttons, so a page cannot
//  press them, and no way past a bad certificate.
//

import SwiftUI
import NookDesign
import NookWeb

struct LoadErrorView: View {
    let session: PageSession

    // The scene and the text keep a reading width however wide the page is.
    private static let sceneWidth: CGFloat = 480, textWidth: CGFloat = 420, margin: CGFloat = 32

    var body: some View {
        if let error = session.loadError {
            let host = error.url.host ?? error.url.absoluteString
            let copy = Self.copy(for: error, host: host)
            VStack(spacing: NookDesign.Spacing.xxxl) {
                NookCornerScene(lampLit: error.kind != .offline)
                    .frame(maxWidth: Self.sceneWidth)
                VStack(spacing: NookDesign.Spacing.md) {
                    Text(copy.title)
                        .font(NookDesign.Font.serifTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(copy.body)
                        .font(NookDesign.Font.bodyRegular)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: Self.textWidth)
                DialogFooter(rightButtons: buttons)
                    .fixedSize()
            }
            .padding(Self.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    /// No Return shortcut: it would take Return from the address bar. A restored tab that has not
    /// loaded yet gets no Close, so a launch while offline cannot close it.
    private var buttons: [DialogButton] {
        let retry = DialogButton(text: "Try Again", variant: .primary) { session.retryFailedLoad() }
        if session.hasCommittedPage {
            return [DialogButton(text: "Go Back") { session.leaveFailedLoad() }, retry]
        }
        if session.isDetached {
            return [DialogButton(text: "Close") { session.leaveFailedLoad() }, retry]
        }
        return [retry]
    }

    private static func copy(for error: PageLoadError, host: String) -> (title: String, body: String) {
        switch error.kind {
        case .offline:
            return ("The lamp's gone out", "You're not connected to the internet.")
        case .hostNotFound:
            return ("This shelf is empty", "Nook couldn't find \(host). Check the address for typos.")
        case .noAnswer:
            return ("Nobody's home", "\(host) isn't answering. The site may be down.")
        case .certificate:
            return ("The seal on this one is broken",
                    "\(host)'s security certificate isn't valid, so Nook didn't open it. Someone could be pretending to be this site.")
        case .other:
            return ("This page wandered off", error.message)
        }
    }
}
