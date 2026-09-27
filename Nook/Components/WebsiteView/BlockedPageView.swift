// Licensed under GPL-3.0. See LICENSE.
//
//  BlockedPageView.swift
//  Nook
//
//  The card over a page the ad blocker stopped from loading. Native buttons, so a page cannot
//  press Continue for itself.
//

import SwiftUI
import NookWeb

struct BlockedPageView: View {
    let session: PageSession

    var body: some View {
        if let url = session.blockedURL {
            let host = url.host ?? url.absoluteString
            StandardDialog {
                DialogHeader(
                    icon: "hand.raised",
                    title: "Nook blocked this page",
                    subtitle: "\(host) is on one of the ad blocker's filter lists."
                )
            } content: {
                EmptyView()
            } footer: {
                DialogFooter(rightButtons: [
                    DialogButton(text: "Continue to \(host)") { session.continueToBlockedPage() },
                    DialogButton(text: session.hasCommittedPage ? "Go Back" : "Close", variant: .primary) {
                        session.leaveBlockedPage()
                    },
                ])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
