// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserToolsConfigCheck.swift
//  Nook
//
//  A saved browser tools config keeps what the person turned off, and a tool added since it
//  was saved starts on.
//
//    S=Packages/NookSettings/Sources/NookSettings
//    swiftc $S/AIModels.swift $S/MCPServerConfig.swift Packages/NookSettings/Checks/BrowserToolsConfigCheck.swift \
//           -o /tmp/tools-config && /tmp/tools-config
//

import Foundation

@main
struct BrowserToolsConfigCheck {
    static func main() throws {
        let twelve = [
            "navigateToURL", "readPageContent", "clickElement", "getInteractiveElements", "extractStructuredData", "summarizePage",
            "searchInPage", "getTabList", "switchTab", "createTab", "getSelectedText", "executeJavaScript",
        ]
        precondition(BrowserToolsConfig.allToolNames == Set(twelve + ["fillField"]))
        precondition(BrowserToolsConfig().enabledTools == BrowserToolsConfig.allToolNames)

        // saved before fillField existed, with one tool turned off
        let enabled = twelve.filter { $0 != "executeJavaScript" }
        let old = try JSONSerialization.data(withJSONObject: ["executionMode": "auto", "enabledTools": enabled])
        var config = try JSONDecoder().decode(BrowserToolsConfig.self, from: old)
        precondition(config.executionMode == .auto)
        precondition(config.enabledTools == Set(enabled + ["fillField"]), "a tool added since starts on; one turned off stays off")

        // turned off after that, saved and read back: it stays off
        config.enabledTools.remove("fillField")
        let again = try JSONDecoder().decode(BrowserToolsConfig.self, from: JSONEncoder().encode(config))
        precondition(again == config && !again.enabledTools.contains("fillField") && !again.enabledTools.contains("executeJavaScript"))

        // everything off stays off, apart from what is new
        let none = try JSONSerialization.data(withJSONObject: ["executionMode": "disabled", "enabledTools": [String]()])
        let off = try JSONDecoder().decode(BrowserToolsConfig.self, from: none)
        precondition(off.enabledTools == ["fillField"])
    }
}
