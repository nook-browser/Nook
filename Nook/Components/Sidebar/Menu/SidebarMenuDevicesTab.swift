// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuDevicesTab.swift
//  Nook
//
//  Read-only tabs from the user's other Macs, one group per device, fed by
//  CloudSyncEngine.otherDevices. Selecting a row opens the URL in this window's
//  current space.
//

import SwiftUI
import NookDesign
import NookSync
import NookUI
import NookWeb

struct SidebarMenuDevicesTab: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @State private var text: String = ""

    private var devices: [DeviceTabsPayload] {
        let all = browserManager.tabs.syncEngine?.otherDevices ?? []
        guard !text.isEmpty else { return all }
        return all.compactMap { device in
            let tabs = device.tabs.filter {
                $0.title.localizedCaseInsensitiveContains(text)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(text)
            }
            guard !tabs.isEmpty else { return nil }
            var filtered = device
            filtered.tabs = tabs
            return filtered
        }
    }

    var body: some View {
        let devices = devices
        ScrollView {
            LazyVStack(spacing: NookDesign.Spacing.rowGap) {
                if devices.isEmpty {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.tertiary)
                        Text(text.isEmpty ? "No other devices" : "No matching tabs")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                        Text(text.isEmpty
                             ? "Tabs open on your other Macs appear here."
                             : "Try searching with a different term")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, NookDesign.Spacing.xxxl)
                } else {
                    ForEach(devices, id: \.deviceID) { device in
                        deviceGroup(device)
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.md)
            .padding(.bottom, NookDesign.Spacing.md)
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            SidebarMenuSearchField(prompt: "Search device tabs...", text: $text)
                .padding(NookDesign.Spacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func deviceGroup(_ device: DeviceTabsPayload) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
            Text(device.name)
                .font(NookDesign.Font.body.weight(.semibold))
            Spacer()
            Text(device.lastSeen, format: .relative(presentation: .named))
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, NookDesign.Spacing.md)
        .contextMenu {
            Button("Remove Device", role: .destructive) {
                browserManager.tabs.syncEngine?.removeDevice(device.deviceID)
            }
        }
        ForEach(Array(device.tabs.enumerated()), id: \.offset) { _, tab in
            DeviceTabRow(tab: tab) {
                browserManager.tabs.open(url: tab.url, in: windowState, placement: .newTab)
            }
        }
    }
}

private struct DeviceTabRow: View {
    let tab: DeviceTabsPayload.Tab
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.title.isEmpty ? (tab.url.host() ?? tab.url.absoluteString) : tab.title)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(tab.url.host() ?? tab.url.absoluteString)
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                NookDesign.Radius.shape(NookDesign.Radius.md)
                    .fill(isHovering ? NookDesign.Surface.fill : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHoverTracking { state in
            isHovering = state
        }
    }
}
