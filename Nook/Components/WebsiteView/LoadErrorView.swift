// Licensed under GPL-3.0. See LICENSE.
//
//  LoadErrorView.swift
//  Nook
//
//  The page shown when a load fails before anything commits. Native buttons, so a page cannot
//  press them, and no way past a bad certificate.
//

import SwiftUI
import NookWeb

struct LoadErrorView: View {
    let session: PageSession

    var body: some View {
        if let error = session.loadError {
            let host = error.url.host ?? error.url.absoluteString
            let copy = Self.copy(for: error, host: host)
            VStack(spacing: 24) {
                NookCornerScene(lampLit: error.kind != .offline)
                    .frame(maxWidth: 480)
                VStack(spacing: 8) {
                    Text(copy.title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                    Text(copy.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                DialogFooter(rightButtons: buttons)
                    .fixedSize()
            }
            .padding(32)
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
