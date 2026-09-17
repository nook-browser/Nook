//
//  TabOrganizerManager.swift
//  Nook
//
//  Public coordinator for LLM-based tab organization.
//  Orchestrates the full flow: collect tabs, build prompt, run inference,
//  parse plan, and present results to the UI for review.
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

    /// The local LLM engine used for inference.
    let engine: LocalLLMEngine

    /// Whether an organization run is currently in progress.
    private(set) var isOrganizing: Bool = false

    /// The last error message, if any.
    private(set) var error: String?

    /// Whether a previous organization can be undone.
    private(set) var canUndo: Bool = false

    /// The change that reverts the last organization, applied with `TabsController.apply(_:)`.
    private var undoChange: Change?

    // MARK: - Init

    init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    /// Convenience initializer that creates its own engine.
    init() {
        self.engine = LocalLLMEngine()
    }

    // MARK: - Organize

    /// Run the full tab organization flow for a space's tabs section.
    ///
    /// 1. Collects the loose tabs (not in a folder) of the space's tabs section.
    /// 2. Builds a prompt with tab metadata and existing folder names.
    /// 3. Runs local LLM inference.
    /// 4. Parses the result into a ``TabOrganizationPlan`` and applies it.
    func organizeTabs(in spaceID: UUID, using tabs: TabsController) async {
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
        guard loose.count <= TabOrganizationPrompt.maxTabs else {
            error = "Too many tabs (\(loose.count)). Maximum is \(TabOrganizationPrompt.maxTabs)."
            Self.log.info("Too many tabs to organize: \(loose.count)")
            return
        }

        isOrganizing = true
        Self.log.info("Starting tab organization for space '\(space.name)' with \(loose.count) tabs")

        do {
            var mapping: [Int: UUID] = [:]
            var inputs: [TabInput] = []
            for (offset, item) in loose.enumerated() {
                let index = offset + 1
                let session = tabs.session(for: item.id)
                let title = item.customTitle.flatMap { $0.isEmpty ? nil : $0 } ?? session?.title ?? item.displayTitle
                guard let url = session?.url ?? item.url else { continue }
                mapping[index] = item.id
                inputs.append(TabInput(index: index, itemID: item.id, title: title, url: url))
            }

            let prompt = TabOrganizationPrompt.build(
                tabs: inputs,
                spaceName: space.name,
                existingFolderNames: section.filter(\.isFolder).map(\.displayTitle)
            )

            let output = try await engine.generate(
                systemPrompt: prompt.system,
                userPrompt: prompt.user,
                maxTokens: 1024
            )

            try Task.checkCancellation()

            Self.log.debug("LLM output: \(output)")

            let parsedPlan = try TabOrganizationPlanParser.parse(output, validRange: 1...loose.count)

            Self.log.info("Organization plan ready: \(parsedPlan.groups.count) groups, \(parsedPlan.renames.count) renames, \(parsedPlan.duplicates.count) duplicate sets")

            // Apply immediately, no preview sheet
            let accepted = AcceptedChanges(
                acceptedGroupIds: Set(parsedPlan.groups.map(\.id)),
                acceptedRenameIds: Set(parsedPlan.renames.map(\.id)),
                acceptedDuplicateIds: Set(parsedPlan.duplicates.map(\.id)),
                applySortOrder: parsedPlan.sort != nil
            )

            let undo = TabOrganizationApplier.apply(
                plan: parsedPlan,
                accepted: accepted,
                tabMapping: mapping,
                spaceID: spaceID,
                tabs: tabs
            )

            undoChange = undo.isEmpty ? nil : undo
            canUndo = undoChange != nil

            Self.log.info("Organization applied")

        } catch is CancellationError {
            // Cancellation (including memory-pressure unload) is not an organization failure.
        } catch {
            let message = error.localizedDescription
            self.error = message
            Self.log.error("Organization failed: \(message)")
        }

        isOrganizing = false
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
