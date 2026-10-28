// Licensed under GPL-3.0. See LICENSE.
//
//  DeveloperBar.swift
//  Nook
//
//  Arc's Developer Mode bar: the page's full address in monospace above the page, and the
//  developer tools a click away. Shown for sites with Developer Mode on (the site panel's
//  Settings section); the tools themselves are the ones Settings > Developer turns on.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb
import NookUI

extension BrowserManager {
    /// Whether the window's page is on a site with Developer Mode on.
    func showsDeveloperBar(in windowState: BrowserWindowState) -> Bool {
        guard !windowState.isIncognito, let settings = nookSettings,
              let host = tabs.selectedSession(in: windowState)?.url.host else { return false }
        return settings.isDeveloperSite(host)
    }

    /// The copy toast with any message, for the developer tools.
    func showWindowToast(_ text: String, in windowState: BrowserWindowState) {
        windowState.copyToastText = text
        windowState.isShowingCopyURLToast = true
        Task { [weak windowState] in
            try? await Task.sleep(for: .seconds(2))
            windowState?.isShowingCopyURLToast = false
            windowState?.copyToastText = nil
        }
    }
}

struct DeveloperBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    let session: PageSession

    @State private var copied = false

    private let height: CGFloat = 38

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: session.url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
            Text(session.url.absoluteString)
                .font(NookDesign.Font.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: NookDesign.Spacing.lg)

            HStack(spacing: NookDesign.Spacing.xxs) {
                tool(copied ? "checkmark" : "link", "Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.url.absoluteString, forType: .string)
                    withAnimation(NookDesign.Motion.quick) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation(NookDesign.Motion.quick) { copied = false }
                    }
                }
                separator
                tool("photo.on.rectangle.angled", "Capture in Portrait Mode", isOn: windowState.isPortraitCaptureVisible) {
                    withAnimation(NookDesign.Motion.spring) { windowState.isPortraitCaptureVisible.toggle() }
                }
                tool("camera", "Copy Screenshot", action: copyScreenshot)
                separator
                tool("terminal", "Console", isOn: devTabShowing(.console)) { browserManager.toggleDevPanel(.console) }
                tool("network", "Network", isOn: devTabShowing(.network)) { browserManager.toggleDevPanel(.network) }
                tool("scope", "Pick Element") { browserManager.startElementPicker() }
                separator
                tool("hammer", "Web Inspector") { browserManager.openWebInspector() }
                tool("gauge.with.needle", "Performance", isOn: devTabShowing(.perf)) { browserManager.toggleDevPanel(.perf) }
            }
        }
        .padding(.horizontal, NookDesign.Spacing.lg)
        .frame(height: height)
        .background(NookDesign.Surface.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(NookDesign.Surface.hairline).frame(height: 1) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var separator: some View {
        Rectangle()
            .fill(NookDesign.Surface.hairline)
            .frame(width: 1, height: NookDesign.Spacing.xl)
            .padding(.horizontal, NookDesign.Spacing.xs)
    }

    private func devTabShowing(_ tab: DevPanelTab) -> Bool {
        windowState.isSidebarAIChatVisible && windowState.devPanelTab == tab
    }

    private func tool(_ symbol: String, _ help: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(help, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .buttonStyle(NookIconButtonStyle())
            .background(isOn ? NookDesign.Surface.fillPressed : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
            .help(help)
    }

    private func copyScreenshot() {
        guard let webView = session.webView else { return }
        webView.takeSnapshot(with: nil) { image, _ in
            guard let image else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            browserManager.showWindowToast("Screenshot copied", in: windowState)
        }
    }
}
