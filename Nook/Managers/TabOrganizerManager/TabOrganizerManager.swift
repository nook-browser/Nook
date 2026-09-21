// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  TabOrganizerManager.swift
//  Nook
//
//  Public coordinator for tab organization on the system language model.
//  Collects the loose tabs, asks the model for folders and titles, applies the plan.
//

import Foundation
import OSLog
import NookTabsCore
import NookWeb

// MARK: - TabOrganizerManager

@Observable
@MainActor
final class TabOrganizerManager {

    // MARK: - Properties

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook",
        category: "TabOrganizerManager"
    )

    /// False when Apple Intelligence is off or the Mac is not eligible; the UI hides the feature then.
    var isAvailable: Bool { TabOrganizationModel.isAvailable }

    static var maxTabs: Int { TabOrganizationModel.maxTabs }

    /// Whether an organization run is currently in progress.
    private(set) var isOrganizing: Bool = false

    /// The last error message, if any.
    private(set) var error: String?

    /// Whether a previous organization can be undone.
    private(set) var canUndo: Bool = false

    /// The change that reverts the last organization, applied with `TabsController.apply(_:)`.
    private var undoChange: Change?

    // MARK: - Organize

    /// Run the full tab organization flow for a space's tabs section.
    ///
    /// 1. Collects the loose tabs (not in a folder) of the space's tabs section.
    /// 2. Finds duplicates by URL.
    /// 3. Asks the model for folders and short titles.
    /// 4. Applies the plan.
    func organizeTabs(in spaceID: UUID, using tabs: TabsController) async {
        guard isAvailable else { return }
        guard !isOrganizing else {
            Self.log.warning("Organization already in progress, ignoring request")
            return
        }
        error = nil

        guard let space = tabs.space(spaceID) else { return }
        let section = tabs.children(of: .tabs(spaceID: spaceID))
        let loose = section.filter { !$0.isFolder }

        guard loose.count >= 3 else {
            error = "Need at least 3 unfiled tabs to organize (found \(loose.count))."
            Self.log.info("Too few tabs to organize: \(loose.count)")
            return
        }
        guard loose.count <= Self.maxTabs else {
            error = "Too many tabs (\(loose.count)). Maximum is \(Self.maxTabs)."
            Self.log.info("Too many tabs to organize: \(loose.count)")
            return
        }

        isOrganizing = true
        Self.log.info("Starting tab organization for space '\(space.name)' with \(loose.count) tabs")

        do {
            var mapping: [Int: UUID] = [:]
            var inputs: [TabInput] = []
            var renamable = Set<Int>()
            for (offset, item) in loose.enumerated() {
                let index = offset + 1
                let session = tabs.session(for: item.id)
                let custom = item.customTitle.flatMap { $0.isEmpty ? nil : $0 }
                let title = custom ?? session?.title ?? item.displayTitle
                guard let url = session?.url ?? item.url else { continue }
                mapping[index] = item.id
                inputs.append(TabInput(index: index, itemID: item.id, title: title, url: url))
                // A title the user typed stays; a short one needs no help.
                if custom == nil, title.count > TabOrganizationModel.cleanTitleLength { renamable.insert(index) }
            }

            let folderIDs = section.filter(\.isFolder).map(\.id)
            let filed = folderIDs.flatMap { tabs.tree.subtree(of: $0) }
                .compactMap { id in tabs.session(for: id)?.url ?? tabs.item(id)?.url }
            let duplicates = TabOrganizationPlan.duplicates(in: inputs, filed: filed)
            let kept = inputs.filter { !duplicates.contains($0.index) }
            let folders = section.filter(\.isFolder).map { folder in
                ExistingFolder(
                    id: folder.id,
                    name: folder.displayTitle,
                    sampleTitles: tabs.children(of: .folder(itemID: folder.id)).prefix(3).map(\.displayTitle)
                )
            }

            // Titles run beside the grouping. They are a bonus: an error there must not cost the grouping.
            async let titled: [TabOrganizationPlan.Rename] = {
                do {
                    return try await TabOrganizationModel.renames(for: kept.filter { renamable.contains($0.index) })
                } catch {
                    Self.log.error("Renames failed: \(error.localizedDescription)")
                    return []
                }
            }()
            let groups = try await TabOrganizationModel.groups(for: kept, existingFolders: folders)
            let renames = await titled
            try Task.checkCancellation()

            let plan = TabOrganizationPlan(groups: groups, renames: renames, duplicates: duplicates)
            Self.log.info("Organization plan ready: \(plan.groups.count) groups, \(plan.renames.count) renames, \(plan.duplicates.count) duplicates")

            let undo = TabOrganizationApplier.apply(plan: plan, tabMapping: mapping, spaceID: spaceID, tabs: tabs)

            undoChange = undo.isEmpty ? nil : undo
            canUndo = undoChange != nil

            Self.log.info("Organization applied")

        } catch is CancellationError {
            // Cancellation is not an organization failure.
        } catch {
            let message = error.localizedDescription
            self.error = message
            Self.log.error("Organization failed: \(message)")
        }

        isOrganizing = false
    }

    // MARK: - Auto-Rename

    /// Shortens the titles of tabs that were just pinned. Skips titles the user typed and short
    /// ones, and drops a result when the tab was renamed, moved out or navigated meanwhile.
    func autoRename(_ itemIDs: [UUID], using tabs: TabsController) {
        guard isAvailable else { return }
        var inputs: [TabInput] = []
        for itemID in itemIDs.prefix(Self.maxTabs) {
            guard let item = tabs.item(itemID), item.customTitle?.isEmpty != false,
                  let url = tabs.session(for: itemID)?.url ?? item.url else { continue }
            let title = tabs.session(for: itemID)?.title ?? item.displayTitle
            guard title.count > TabOrganizationModel.cleanTitleLength else { continue }
            inputs.append(TabInput(index: inputs.count + 1, itemID: itemID, title: title, url: url))
        }
        guard !inputs.isEmpty else { return }
        Task {
            do {
                for rename in try await TabOrganizationModel.renames(for: inputs) {
                    let input = inputs[rename.tab - 1]
                    guard let item = tabs.item(input.itemID), item.customTitle?.isEmpty != false,
                          case .pinned = tabs.tree.section(of: input.itemID),
                          (tabs.session(for: input.itemID)?.title ?? item.displayTitle) == input.title else { continue }
                    tabs.rename(input.itemID, rename.name)
                }
            } catch {
                Self.log.error("Auto-rename failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Undo

    /// Reverts the last organization: folders it created go away, moved and renamed tabs go back,
    /// closed duplicates return with their ids.
    func undoLastOrganization(using tabs: TabsController) {
        guard let change = undoChange else {
            Self.log.warning("undoLastOrganization called with nothing to undo")
            return
        }
        Self.log.info("Undoing last organization")
        tabs.apply(change)
        undoChange = nil
        canUndo = false
        Self.log.info("Undo complete")
    }
}
