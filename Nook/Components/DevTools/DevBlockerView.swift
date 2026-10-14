// Licensed under GPL-3.0. See LICENSE.
//
//  DevBlockerView.swift
//  Nook
//
//  Blocker tab: what the content blocker did to this page, and the switch to allow the site.
//

import AppKit
import SwiftUI
import NookBlocker
import NookDesign
import NookWeb
import NookUI

struct DevBlockerView: View {
    let capture: DevCapture?
    let session: PageSession?
    @EnvironmentObject var browserManager: BrowserManager

    private var blocker: ContentBlockerManager { browserManager.contentBlockerManager }
    private var host: String? { session?.url.host }

    var body: some View {
        if let capture {
            List {
                Section {
                    status
                }
                if !capture.blockedHosts.isEmpty {
                    Section("Blocked by Host") {
                        ForEach(capture.blockedHosts, id: \.host) { row in
                            HStack {
                                Text(row.host).font(NookDesign.Font.secondary).lineLimit(1)
                                Spacer()
                                Text("\(row.count)").font(NookDesign.Font.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let rules = capture.pageRules, !rules.scriptlets.isEmpty || !rules.procedural.isEmpty {
                    Section("Page Rules") {
                        if !rules.scriptlets.isEmpty {
                            Text("Scriptlets: " + rules.scriptlets.joined(separator: ", "))
                                .font(NookDesign.Font.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        ForEach(Array(rules.procedural.enumerated()), id: \.offset) { _, rule in
                            Text(rule).font(NookDesign.Font.caption.monospaced()).lineLimit(3).textSelection(.enabled)
                        }
                    }
                }
                Section("Actions") {
                    if capture.blocked.items.isEmpty {
                        Text("Nothing blocked on this page.")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(capture.blocked.items.reversed()) { entry in
                        DevBlockRow(entry: entry)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            DevPanelEmpty()
        }
    }

    @ViewBuilder
    private var status: some View {
        if !blocker.isEnabled {
            Text("Ad blocking is off.").font(NookDesign.Font.secondary).foregroundStyle(.secondary)
        } else if let host {
            Toggle("Block on \(host)", isOn: Binding(
                get: { !blocker.isDomainAllowed(host) },
                set: { blocker.allowDomain(host, allowed: !$0) }
            ))
            .font(NookDesign.Font.secondary)
            if let session, !blocker.shouldApplyBlocking(to: session), !blocker.isDomainAllowed(host) {
                Text("Not blocking on this page: sign-in or temporarily turned off.")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DevBlockRow: View {
    let entry: DevBlockEntry

    private var label: String {
        switch entry.action {
        case .blocked: return "Blocked"
        case .cookiesBlocked: return "Cookies blocked"
        case .madeHTTPS: return "Made HTTPS"
        case .redirected: return "Redirected"
        case .strippedParams: return "Tracking removed"
        case .skippedRedirect: return "Redirect skipped"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
            HStack(spacing: NookDesign.Spacing.sm) {
                Text(label)
                    .font(NookDesign.Font.captionStrong)
                    .foregroundStyle(entry.action == .blocked ? .red : .secondary)
                Text(entry.host).font(NookDesign.Font.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(entry.url)
                .font(NookDesign.Font.caption.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let target = entry.target {
                Text("→ " + target)
                    .font(NookDesign.Font.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
        }
    }
}
