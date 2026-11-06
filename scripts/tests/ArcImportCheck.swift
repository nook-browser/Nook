// Licensed under GPL-3.0. See LICENSE.
//
//  ArcImportCheck.swift
//  Nook
//
//  Arc's sidebar parses in order with nesting intact. Compiles the shipped source directly:
//
//    swiftc Nook/Managers/ImportManager/Arc.swift Packages/NookSettings/Sources/NookSettings/SiteRoutingRule.swift scripts/tests/ArcImportCheck.swift \
//           -o /tmp/arc-import-check && /tmp/arc-import-check [StorableSidebar.json]
//
//  With a path it also prints a summary of that file.
//

import Foundation

@main
struct ArcImportCheck {
    static func main() throws {
        let result = try parseArcSidebarData(Data(fixture.utf8))
        precondition(result.spaces.map(\.title) == ["Work", "Home"], "spaces keep Arc's order")

        let work = result.spaces[0]
        precondition(work.profile == "default")
        precondition(work.accentHex == "#FF8000", "extended sRGB clamps")
        precondition(work.pinned == [
            .tab(url: "https://b.example", title: "B page", customTitle: nil),
            .folder(title: "Outer", children: [
                .folder(title: "Inner", children: [.tab(url: "https://deep.example", title: nil, customTitle: nil)]),
                .tab(url: "https://a.example", title: "A page", customTitle: "Renamed"),
            ]),
        ], "childrenIds order, nested folders, custom names")
        precondition(work.unpinned == [
            .tab(url: "https://left.example", title: nil, customTitle: nil),
            .tab(url: "https://right.example", title: nil, customTitle: nil),
        ], "a split view keeps its tabs in place; a tab without a URL is skipped")

        let home = result.spaces[1]
        precondition(home.profile == "Profile 1", "custom profile keyed by directory")
        precondition(home.pinned == [
            .tab(url: "https://home.example", title: nil, customTitle: nil),
            .tab(url: "https://child.example", title: nil, customTitle: nil),
        ], "newContainerIDs fallback, a tab's children follow it, currentURL fallback")
        precondition(home.accentHex == nil)

        precondition(result.favorites["default"] == [.tab(url: "https://fav.example", title: "Fav", customTitle: nil)])
        precondition(result.favorites["Profile 1"] == [.tab(url: "https://fav2.example", title: nil, customTitle: nil)])
        let extensions = parseChromiumExtensionIDs([Data("""
        {"extensions": {"settings": {
          "ldciclpbkaobfbicjebamaapbfplfjen": {"location": 5, "from_webstore": false},
          "nngceckbapebfimnlniiiahkandclblb": {"location": 1, "from_webstore": true, "state": 1, "disable_reasons": []},
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa": {"location": 1, "from_webstore": true, "disable_reasons": [1]},
          "cjpalhdlnbpafiamejdnhcphjbkeiagm": {"location": 1, "from_webstore": true}
        }}}
        """.utf8), Data(#"{"extensions": {"settings": {"cjpalhdlnbpafiamejdnhcphjbkeiagm": {"from_webstore": true}}}}"#.utf8)])
        precondition(extensions == ["cjpalhdlnbpafiamejdnhcphjbkeiagm", "nngceckbapebfimnlniiiahkandclblb"],
                     "store installs only, enabled only, once each")

        precondition(work.id == "S1" && home.id == "S2")

        func route(_ pattern: String, _ style: String = "contains", _ space: String = "S1") -> String {
            #"{"sourceComponents": [{"id": "x", "componentType": {"urlMatch": {"_0": {"\#(style)": {}}, "_1": "\#(pattern)"}}}], "destination": {"space": {"_0": {"space": {"_0": "\#(space)"}}}}, "id": "r"}"#
        }
        let little = #"{"sourceComponents": [{"componentType": {"urlMatch": {"_0": {"contains": {}}, "_1": "a.com"}}}], "destination": {"littleArc": {"_0": {"mostRecent": {}}}}}"#
        let profile = #"{"sourceComponents": [{"componentType": {"urlMatch": {"_0": {"contains": {}}, "_1": "b.com"}}}], "destination": {"space": {"_0": {"profile": {"_0": "P"}}}}}"#
        let routing = parseArcLinkRouting(Data("""
        {"version": 1, "rules": [\([route("meet.google.com"), route("docs.google.com/spreadsheets"), route("x.com", "matches"),
            little, profile, route("github"), route("https://www.Example.com/"), route("meet.google.com"),
            route("lost.com", "contains", "GONE"), route("a.com/b c")].joined(separator: ","))]}
        """.utf8))
        precondition(routing.routes.count == 7 && routing.skipped == 3, "matches, Little Arc and profile rules are skipped")
        let mapped = UUID(), kept = SiteRoutingRule(domain: "example.com", targetSpaceId: mapped)
        let rules = arcSiteRules(routing, spaceIDs: ["S1": mapped], existing: [kept])
        precondition(rules.rules.map(\.domain) == ["meet.google.com", "docs.google.com"], "host rules in order; duplicates dropped")
        precondition(rules.rules[1].pathPrefix == "/spreadsheets" && rules.rules[0].pathPrefix == nil)
        precondition(rules.rules.allSatisfy { $0.targetSpaceId == mapped })
        precondition(rules.skipped == 3 + 3, "no dot, unknown space and bad path are skipped too")

        let other = UUID()
        let again = arcSiteRules(parseArcLinkRouting(Data("""
        {"rules": [\([route("meet.google.com"), route("GitHub.com/MyOrg")].joined(separator: ","))]}
        """.utf8)), spaceIDs: ["S1": other], existing: [SiteRoutingRule(domain: "meet.google.com", targetSpaceId: mapped)])
        precondition(again.rules.count == 1 && again.rules[0].domain == "github.com" && again.rules[0].pathPrefix == "/MyOrg",
                     "same domain and path to another space is dropped; path keeps its case")

        precondition(arcImportSummary(spaces: 4, tabs: 87, folders: 12, rules: 3) == "4 spaces, 87 tabs, 12 folders and 3 Air Traffic Control rules.")
        precondition(arcImportSummary(spaces: 1, tabs: 0, folders: 1, rules: 1) == "1 space, 1 folder and 1 Air Traffic Control rule.")
        precondition(arcImportSummary(spaces: 0, tabs: 0, folders: 0, rules: 2) == "2 Air Traffic Control rules.")

        let empty = try parseArcSidebarData(Data("{}".utf8))
        precondition(empty.spaces.isEmpty)

        if CommandLine.arguments.count > 1 {
            let real = try parseArcSidebarData(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            func count(_ nodes: [ArcNode]) -> (tabs: Int, folders: Int) {
                nodes.reduce((0, 0)) { sum, node in
                    switch node {
                    case .tab: return (sum.0 + 1, sum.1)
                    case .folder(_, let children):
                        let inner = count(children)
                        return (sum.0 + inner.tabs, sum.1 + 1 + inner.folders)
                    }
                }
            }
            for space in real.spaces {
                let pinned = count(space.pinned), today = count(space.unpinned)
                let favorites = real.favorites[space.profile]?.count ?? 0
                print("\(space.title) [\(space.profile)] \(space.accentHex ?? "-"): \(favorites) favorites, "
                      + "\(pinned.tabs) pinned tabs in \(pinned.folders) folders, \(today.tabs) today tabs")
            }
        }
        print("ArcImportCheck passed")
    }

    static let fixture = """
    {"version": 1, "sidebar": {"containers": [{"global": {}}, {
      "topAppsContainerIDs": [{"default": true}, "FAV1", {"custom": {"_0": {"directoryBasename": "Profile 1", "machineID": "M"}}}, "FAV2"],
      "spaces": [
        "S1", {"id": "S1", "title": "Work", "profile": {"default": true},
               "containerIDs": ["unpinned", "U1", "pinned", "P1"],
               "customInfo": {"windowTheme": {"primaryColorPalette": {"midTone": {"red": 1.2, "green": 0.5, "blue": -0.3, "alpha": 1}}}}},
        "S2", {"id": "S2", "title": "Home", "profile": {"custom": {"_0": {"directoryBasename": "Profile 1"}}},
               "newContainerIDs": [{"unpinned": {"_0": {"shared": {}}}}, "U2", {"pinned": {}}, "P2"]}
      ],
      "items": [
        "FAV1", {"id": "FAV1", "childrenIds": ["F1"], "parentID": null, "data": {"itemContainer": {"containerType": {"topApps": {"_0": {"default": {}}}}}}},
        "F1", {"id": "F1", "childrenIds": [], "parentID": "FAV1", "title": null, "data": {"tab": {"savedURL": "https://fav.example", "savedTitle": "Fav"}}},
        "FAV2", {"id": "FAV2", "childrenIds": ["F2"], "parentID": null, "data": {"itemContainer": {}}},
        "F2", {"id": "F2", "childrenIds": [], "parentID": "FAV2", "data": {"tab": {"savedURL": "https://fav2.example"}}},
        "P1", {"id": "P1", "childrenIds": ["T2", "OUT"], "parentID": null, "data": {"itemContainer": {"containerType": {"spaceItems": {"_0": "S1"}}}}},
        "OUT", {"id": "OUT", "childrenIds": ["IN", "T1"], "parentID": "P1", "title": "Outer", "data": {"list": {}}},
        "IN", {"id": "IN", "childrenIds": ["T3", "OUT"], "parentID": "OUT", "title": "Inner", "data": {"list": {}}},
        "T1", {"id": "T1", "childrenIds": [], "parentID": "OUT", "title": "Renamed", "data": {"tab": {"savedURL": "https://a.example", "savedTitle": "A page"}}},
        "T2", {"id": "T2", "childrenIds": [], "parentID": "P1", "title": "B page", "data": {"tab": {"savedURL": "https://b.example", "savedTitle": "B page"}}},
        "T3", {"id": "T3", "childrenIds": [], "parentID": "IN", "data": {"tab": {"savedURL": "https://deep.example"}}},
        "U1", {"id": "U1", "childrenIds": ["SPLIT", "EMPTY"], "parentID": null, "data": {"itemContainer": {}}},
        "SPLIT", {"id": "SPLIT", "childrenIds": ["L", "R"], "parentID": "U1", "data": {"splitView": {"layoutOrientation": "horizontal"}}},
        "L", {"id": "L", "childrenIds": [], "parentID": "SPLIT", "data": {"tab": {"savedURL": "https://left.example"}}},
        "R", {"id": "R", "childrenIds": [], "parentID": "SPLIT", "data": {"tab": {"savedURL": "https://right.example"}}},
        "EMPTY", {"id": "EMPTY", "childrenIds": [], "parentID": "U1", "data": {"tab": {}}},
        "P2", {"id": "P2", "childrenIds": ["H1"], "parentID": null, "data": {"itemContainer": {}}},
        "H1", {"id": "H1", "childrenIds": ["H2"], "parentID": "P2", "data": {"tab": {"savedURL": "https://home.example"}}},
        "H2", {"id": "H2", "childrenIds": [], "parentID": "H1", "data": {"tab": {"savedURL": "", "currentURL": "https://child.example"}}},
        "U2", {"id": "U2", "childrenIds": [], "parentID": null, "data": {"itemContainer": {}}}
      ]
    }]}}
    """
}
