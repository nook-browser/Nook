//
//  ProfileManager.swift
//  Nook
//
//  Manages runtime profiles and their SwiftData persistence.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class ProfileManager: ObservableObject {
    let context: ModelContext
    @Published var profiles: [Profile] = []
    
    // MARK: - Ephemeral Profiles (Incognito)
    /// Active ephemeral profiles (one per incognito window)
    private var ephemeralProfiles: [UUID: Profile] = [:]  // windowId -> profile
    
    init(context: ModelContext) {
        self.context = context
        loadProfiles()
    }

    // MARK: - Loading
    func loadProfiles() {
        do {
            let descriptor = FetchDescriptor<ProfileEntity>(
                sortBy: [SortDescriptor(\.index, order: .forward)]
            )
            let entities = try context.fetch(descriptor)
            self.profiles = entities.map { e in
                Profile(id: e.id, name: e.name, icon: e.icon)
            }
            // Normalize indices if not sequential 0..n-1
            let expected = Array(0..<entities.count)
            let actual = entities.map { $0.index }
            if actual != expected { persistProfiles() }
        } catch {
            print("[ProfileManager] Failed to load profiles: \(error)")
            self.profiles = []
        }
    }

    // MARK: - CRUD
    @discardableResult
    func createProfile(name: String, icon: String = "person.crop.circle") -> Profile {
        // Next index is current count (append to end)
        let nextIndex = profiles.count
        let profile = Profile(name: name, icon: icon)
        let entity = ProfileEntity(id: profile.id, name: name, icon: icon, index: nextIndex)
        context.insert(entity)
        do { try context.save() } catch { print("[ProfileManager] Save failed during create: \(error)") }
        profiles.append(profile)
        return profile
    }

    func deleteProfile(_ profile: Profile) -> Bool {
        guard profiles.count > 1 else { return false } // prevent deleting last profile
        // Remove from SwiftData first; if persistence fails, do not mutate runtime state
        do {
            let pid = profile.id
            let predicate = #Predicate<ProfileEntity> { $0.id == pid }
            if let entity = try context.fetch(FetchDescriptor<ProfileEntity>(predicate: predicate)).first {
                context.delete(entity)
            }
            try context.save()
        } catch {
            print("[ProfileManager] Delete failed: \(error)")
            return false
        }
        // Remove from runtime and reindex
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles.remove(at: idx)
        }
        persistProfiles()
        return true
    }

    func persistProfiles() {
        do {
            // Fetch all existing entities
            let all = try context.fetch(FetchDescriptor<ProfileEntity>())
            var byId: [UUID: ProfileEntity] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

            // Update or insert to match runtime profiles order
            for (index, p) in profiles.enumerated() {
                if let e = byId[p.id] {
                    e.name = p.name
                    e.icon = p.icon
                    e.index = index
                } else {
                    let e = ProfileEntity(id: p.id, name: p.name, icon: p.icon, index: index)
                    context.insert(e)
                    byId[p.id] = e
                }
            }
            // Optionally, remove entities not present in runtime array
            let keep = Set(profiles.map { $0.id })
            for (id, e) in byId where !keep.contains(id) { context.delete(e) }
            try context.save()
        } catch {
            print("[ProfileManager] Persist failed: \(error)")
        }
    }

    func ensureDefaultProfile() {
        if profiles.isEmpty {
            _ = createProfile(name: "Default", icon: "person.crop.circle")
        }
    }
    
    // MARK: - Ephemeral Profile Management
    
    /// Create a new ephemeral profile for an incognito window
    func createEphemeralProfile(for windowId: UUID) -> Profile {
        let profile = Profile.createEphemeral()
        ephemeralProfiles[windowId] = profile
        print("🔒 [ProfileManager] Created ephemeral profile for window: \(windowId)")
        return profile
    }
    
    /// Remove an ephemeral profile when incognito window closes
    func removeEphemeralProfile(for windowId: UUID) {
        if let profile = ephemeralProfiles.removeValue(forKey: windowId) {
            print("🔒 [ProfileManager] Removed ephemeral profile: \(profile.id) for window: \(windowId)")
        }
    }
    
    /// Get ephemeral profile for a window
    func ephemeralProfile(for windowId: UUID) -> Profile? {
        return ephemeralProfiles[windowId]
    }
    
    /// Check if a profile ID is an ephemeral profile
    func isEphemeralProfile(_ profileId: UUID) -> Bool {
        return ephemeralProfiles.values.contains { $0.id == profileId }
    }
}
