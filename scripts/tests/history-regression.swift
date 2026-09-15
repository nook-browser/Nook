import Foundation
import SwiftData

@main
struct HistoryRegression {
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let container = try ModelContainer(for: HistoryEntity.self, configurations: ModelConfiguration(url: url))
        if CommandLine.arguments.contains("seed") {
            let context = ModelContext(container)
            context.insert(HistoryEntity(url: "https://legacy.example", title: "Legacy"))
            try context.save()
            print("Seeded pre-index schema")
            return
        }
        let store = await Task.detached { HistoryStore(modelContainer: container) }.value
        let profile = UUID(), other = UUID()
        let now = Date()
        let legacy = URL(string: "https://legacy.example")!
        await store.addVisits([
            HistoryVisit(url: legacy, title: "Adopted", timestamp: now, tabId: nil, profileId: profile),
            HistoryVisit(url: legacy, title: "Other profile", timestamp: now, tabId: nil, profileId: other),
            HistoryVisit(url: legacy, title: "Old import", timestamp: now.addingTimeInterval(-1000), tabId: nil, profileId: profile)
        ])
        let all = await store.history(days: 7, profile: nil, page: 0, pageSize: 100)
        precondition(all.entries.count == 2, "Nil-profile adoption must not merge another profile")
        let adopted = await store.history(days: 7, profile: profile, page: 0, pageSize: 1)
        precondition(adopted.entries.count == 1 && !adopted.hasMore)
        precondition(adopted.entries[0].title == "Adopted" && adopted.entries[0].visitCount == 3)
        precondition(adopted.entries[0].lastVisited == now, "Old imports must preserve latest visit")
        let rows = (0..<1200).map { index in
            HistoryVisit(url: URL(string: "https://test.example/\(index)")!, title: "Café \(index)",
                         timestamp: now.addingTimeInterval(Double(index)), tabId: nil,
                         profileId: index.isMultiple(of: 2) ? profile : other)
        }
        await store.addVisits(rows)
        let page = await store.search(query: "CAFÉ", profile: profile, page: 1, pageSize: 50)
        precondition(page.entries.count == 50 && page.hasMore)
        precondition(page.entries.first?.title == "Café 1098", "Profile filtering must precede pagination")
        let last = await store.search(query: "Café", profile: profile, page: 11, pageSize: 50)
        precondition(last.entries.count == 50 && !last.hasMore)
        await store.clear(days: 0, profile: profile)
        let otherEntries = await store.history(days: 7, profile: other, page: 0, pageSize: 1000)
        precondition(otherEntries.entries.count == 601, "Clearing one profile must preserve another")
        let manager = await MainActor.run { HistoryManager(context: ModelContext(container), profileId: profile) }
        manager.addVisit(url: URL(string: "https://queued.example")!, title: "Queued", tabId: nil)
        let queued = await manager.searchHistory(query: "queued")
        precondition(queued.count == 1, "Reads must wait for queued writes")
        manager.addVisit(url: URL(string: "https://private.example")!, title: "Private", tabId: nil, isEphemeral: true)
        let privateRows = await manager.searchHistory(query: "private.example")
        precondition(privateRows.isEmpty)
        print("PASS: index migration, profile isolation/adoption, batched writes, recency, localized paginated search, write ordering and incognito")
    }
}
