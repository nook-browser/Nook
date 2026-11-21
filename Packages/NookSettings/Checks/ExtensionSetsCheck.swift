// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionSetsCheck.swift
//  swiftc Packages/NookSettings/Sources/NookSettings/ExtensionSets.swift \
//    Packages/NookSettings/Checks/ExtensionSetsCheck.swift -o /tmp/esc && /tmp/esc
//

import Foundation

@main
struct ExtensionSetsCheck {
    static func main() {
        let d = UUID()
        let (p1, p2, p3, p4, p5) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let all = [p1, p2, p3, p4, p5]
        var sets = ExtensionSets()

        // Upgrade: nobody has an entry, everyone is in the default set.
        precondition(sets.setID(forProfile: p1, defaultSet: d) == d)

        // Bain's example: 2 goes Separate and starts its own set.
        let (s, g0) = sets.separate(p2, profiles: all, defaultSet: d)
        precondition(s != d && g0.isEmpty)
        precondition(sets.choices(profiles: [p1, p2, p3, p4], defaultSet: d) == [
            ExtensionSetChoice(set: d, members: [p1, p3, p4]),
            ExtensionSetChoice(set: s, members: [p2]),
        ])
        precondition(sets.separate(p2, profiles: all, defaultSet: d) == (s, []), "already alone keeps its set")

        // 5 syncs with 2.
        precondition(sets.sync(p5, with: s, profiles: all, defaultSet: d).isEmpty)
        precondition(sets.setID(forProfile: p5, defaultSet: d) == s)

        // 5 going Separate gets a new set, since 2 still uses s.
        let (s5, _) = sets.separate(p5, profiles: all, defaultSet: d)
        precondition(s5 != s && s5 != d)
        sets.sync(p5, with: s, profiles: all, defaultSet: d)
        precondition(sets.dormant[p5] == [s5])

        // 2 leaves while 5 remains: nothing dormant for 2, nothing deleted.
        precondition(sets.sync(p2, with: d, profiles: all, defaultSet: d).isEmpty)
        precondition(sets.membership[p2] == nil && sets.dormant[p2] == nil)

        // 5, the last member, leaves s: s goes dormant under 5 beside its older dormant s5.
        precondition(sets.sync(p5, with: d, profiles: all, defaultSet: d).isEmpty)
        precondition(sets.dormant[p5] == [s5, s])
        precondition(sets.separate(p5, profiles: all, defaultSet: d) == (s, []), "Separate restores the newest dormant set")
        precondition(sets.dormant[p5] == [s5])

        // Deleting a profile while another still uses its set deletes nothing of that set.
        sets.sync(p2, with: s, profiles: all, defaultSet: d)
        precondition(sets.profileDeleted(p2, defaultSet: d).isEmpty)
        precondition(Set(sets.profileDeleted(p5, defaultSet: d)) == [s, s5], "a profile's sets go with it")

        // The default set is never garbage, and default members have no entry.
        precondition(sets.profileDeleted(p1, defaultSet: d).isEmpty)
        sets.sync(p3, with: d, profiles: all, defaultSet: d)
        precondition(sets.membership.isEmpty && sets.dormant.isEmpty)

        // The last profile to leave the default set remembers it, and Separate brings it back:
        // otherwise the extensions it had could never be reached again.
        var two = ExtensionSets()
        let own = two.separate(p1, profiles: [p1, p2], defaultSet: d).set
        precondition(two.sync(p2, with: own, profiles: [p1, p2], defaultSet: d).isEmpty)
        precondition(two.dormant[p2] == [d])
        let back = two.separate(p2, profiles: [p1, p2], defaultSet: d)
        precondition(back.set == d && back.garbage.isEmpty)
        precondition(two.membership[p2] == nil && two.dormant[p2] == nil)

        // A new profile that is alone in the default set still starts empty when it asks for Separate.
        let fresh = two.separate(p3, profiles: [p1, p3], defaultSet: d)
        precondition(fresh.set != d && fresh.set != own)

        // A second set left empty never pushes out the first: a set goes only with its profile.
        var kept = ExtensionSets()
        let trio = [p1, p2, p3]
        let a = kept.separate(p1, profiles: trio, defaultSet: d).set
        let b = kept.separate(p2, profiles: trio, defaultSet: d).set
        precondition(kept.sync(p1, with: b, profiles: trio, defaultSet: d).isEmpty)
        let c = kept.separate(p2, profiles: trio, defaultSet: d).set
        precondition(c != a && c != b && c != d)
        precondition(kept.sync(p1, with: c, profiles: trio, defaultSet: d).isEmpty, "leaving a second set keeps the first")
        precondition(kept.dormant[p1] == [a, b])
        precondition(kept.separate(p1, profiles: trio, defaultSet: d) == (b, []))
        precondition(Set(kept.profileDeleted(p1, defaultSet: d)) == [a, b])

        // The registry idles the default set while `choices` lists no profile in it, and wakes it when one joins.
        var idle = ExtensionSets()
        let duo = [p1, p2]
        let x = idle.separate(p1, profiles: duo, defaultSet: d).set
        precondition(idle.choices(profiles: duo, defaultSet: d).contains { $0.set == d }, "p2 still runs the default set")
        let y = idle.separate(p2, profiles: duo, defaultSet: d).set
        precondition(!idle.choices(profiles: duo, defaultSet: d).contains { $0.set == d }, "every profile Separate")
        precondition(idle.sync(p2, with: d, profiles: duo, defaultSet: d).isEmpty && x != y)
        precondition(idle.choices(profiles: duo, defaultSet: d).contains { $0.set == d }, "a profile joined it again")

        // Survives a round trip through JSON, the way settings store it.
        var stored = ExtensionSets()
        _ = stored.separate(p4, profiles: all, defaultSet: d)
        let data = try! JSONEncoder().encode(stored)
        precondition(try! JSONDecoder().decode(ExtensionSets.self, from: data) == stored)
        print("ExtensionSetsCheck passed")
    }
}
