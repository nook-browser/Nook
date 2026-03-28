//
//  AirTrafficControlSettingsView.swift
//  Nook
//

import SwiftUI

struct AirTrafficControlSettingsView: View {
    @Environment(\.nookSettings) var nookSettings
    @EnvironmentObject var browserManager: BrowserManager

    @State private var showingAddSheet = false
    @State private var editingRule: SiteRoutingRule?

    var body: some View {
        Form {
            Section {
                Text("Automatically route websites to specific spaces. When you navigate to a matching domain, a new tab opens in the designated space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Rules") {
                if nookSettings.siteRoutingRules.isEmpty {
                    Text("No routing rules configured.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(nookSettings.siteRoutingRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete(perform: deleteRules)
                }
            }

            Section {
                HStack {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            RuleEditSheet(
                browserManager: browserManager,
                onSave: { rule in
                    browserManager.siteRoutingManager.addRule(rule)
                }
            )
        }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(
                browserManager: browserManager,
                existingRule: rule,
                onSave: { updated in
                    browserManager.siteRoutingManager.updateRule(updated)
                }
            )
        }
    }

    private func ruleRow(_ rule: SiteRoutingRule) -> some View {
        let space = browserManager.tabManager.spaces.first(where: { $0.id == rule.targetSpaceId })
        let profile = browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId })

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.domain)
                        .fontWeight(.medium)
                    if let pp = rule.pathPrefix, !pp.isEmpty {
                        Text(pp)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let space {
                        Image(systemName: space.icon)
                            .font(.caption)
                        Text(space.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Space deleted")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if browserManager.profileManager.profiles.count > 1, let profile {
                        Text("(\(profile.name))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    browserManager.siteRoutingManager.updateRule(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingRule = rule
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            let rule = nookSettings.siteRoutingRules[index]
            browserManager.siteRoutingManager.deleteRule(id: rule.id)
        }
    }
}

// MARK: - Add/Edit Sheet

private struct RuleEditSheet: View {
    let browserManager: BrowserManager
    var existingRule: SiteRoutingRule?
    let onSave: (SiteRoutingRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nookSettings) var nookSettings

    @State private var domain: String = ""
    @State private var pathPrefix: String = ""
    @State private var selectedSpaceId: UUID?
    @State private var selectedProfileId: UUID?
    @State private var isEnabled: Bool = true
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Website") {
                    TextField("Domain (e.g. github.com)", text: $domain)
                        .textFieldStyle(.roundedBorder)
                    TextField("Path prefix (optional, e.g. /myorg)", text: $pathPrefix)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Destination") {
                    Picker("Space", selection: $selectedSpaceId) {
                        Text("Select a space").tag(nil as UUID?)
                        ForEach(groupedSpaces, id: \.profileName) { group in
                            Section(group.profileName) {
                                ForEach(group.spaces) { space in
                                    Label(space.name, systemImage: space.icon)
                                        .tag(space.id as UUID?)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existingRule != nil ? "Save" : "Add Rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || selectedSpaceId == nil)
            }
            .padding()
        }
        .frame(width: 400, height: 360)
        .onAppear {
            if let rule = existingRule {
                domain = rule.domain
                pathPrefix = rule.pathPrefix ?? ""
                selectedSpaceId = rule.targetSpaceId
                selectedProfileId = rule.targetProfileId
                isEnabled = rule.isEnabled
            }
        }
        .onChange(of: selectedSpaceId) { _, newValue in
            if let spaceId = newValue,
               let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) {
                selectedProfileId = space.profileId ?? browserManager.profileManager.profiles.first?.id
            }
        }
    }

    private var groupedSpaces: [(profileName: String, spaces: [Space])] {
        let profiles = browserManager.profileManager.profiles.filter { !$0.isEphemeral }
        var result = profiles.map { profile in
            let spaces = browserManager.tabManager.spaces.filter { $0.profileId == profile.id }
            return (profileName: profile.name, spaces: spaces)
        }
        let unassigned = browserManager.tabManager.spaces.filter { $0.profileId == nil && !$0.isEphemeral }
        if !unassigned.isEmpty {
            result.append((profileName: "Unassigned", spaces: unassigned))
        }
        return result
    }

    private func save() {
        let normalized = SiteRoutingRule.normalizeDomain(domain)
        guard !normalized.isEmpty else {
            validationError = "Domain is required."
            return
        }

        let pp = pathPrefix.trimmingCharacters(in: .whitespaces)
        let effectivePathPrefix: String? = pp.isEmpty ? nil : pp

        let isDuplicate = nookSettings.siteRoutingRules.contains { existing in
            existing.id != existingRule?.id &&
            existing.domain == normalized &&
            existing.pathPrefix == effectivePathPrefix
        }
        if isDuplicate {
            validationError = "A rule for this domain and path already exists."
            return
        }

        guard let spaceId = selectedSpaceId,
              let profileId = selectedProfileId else {
            validationError = "Please select a target space."
            return
        }

        let rule = SiteRoutingRule(
            id: existingRule?.id ?? UUID(),
            domain: normalized,
            pathPrefix: effectivePathPrefix,
            targetSpaceId: spaceId,
            targetProfileId: profileId,
            isEnabled: isEnabled
        )
        onSave(rule)
        dismiss()
    }
}
