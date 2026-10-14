// Licensed under GPL-3.0. See LICENSE.
//
//  DevPickCheck.swift
//  Nook
//
//  Picker message parsing and the Markdown an agent receives.
//
//    swiftc -parse-as-library Packages/NookWeb/Sources/NookWeb/DevTools/DevLog.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevEntries.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevPick.swift \
//           Packages/NookWeb/Checks/DevPickCheck.swift -o /tmp/devpick && /tmp/devpick
//

import Foundation

@main
struct DevPickCheck {
    static func main() {
        precondition(DevPickedElement(message: "x") == nil)
        precondition(DevPickedElement(message: ["url": "u"]) == nil, "missing fields")

        var e = DevPickedElement(message: [
            "url": "https://a.test/", "selector": "#save", "tag": "button", "role": "button", "name": "Save\nnow",
            "rect": ["x": 10.4, "y": 20, "w": 120, "h": 32], "html": "<button id=\"save\">Save</button>",
            "styles": [["display", "flex"], ["bad"]], "source": "",
        ])!
        precondition(e.styles.count == 1, "malformed style pairs dropped")
        precondition(e.source == "", "the script's empty source is kept until hints fill it")
        e.source = nil
        e.apply(hints: ["react": ["SaveButton", "Toolbar", "App"], "source": "src/Save.tsx:12"])
        precondition(e.components == ["App", "Toolbar", "SaveButton"], "outermost first")
        precondition(e.source == "src/Save.tsx:12")
        var minified = e
        minified.apply(hints: ["react": ["tR", "K", "$", "z", "Layout"]])
        precondition(minified.components == ["Layout"], "minified names dropped")
        e.apply(hints: ["source": "other.tsx:1"])
        precondition(e.source == "src/Save.tsx:12", "a data-attribute or first source wins")

        var err = DevConsoleEntry(level: "error", message: "boom\nstack", location: "app.js:4")
        err.repeatCount = 1
        var bad = DevNetworkEntry(key: "f", kind: "fetch", method: "GET", url: "https://a.test/api")
        bad.status = 500
        let md = DevHandoff.markdown(element: e, errors: [err], failed: [bad], imagePath: "/tmp/p.png")
        precondition(md.contains("- Role: button \"Save now\""), "name on one line")
        precondition(md.contains("- Box: 120×32 at (10, 20)"))
        precondition(md.contains("- Components: App > Toolbar > SaveButton"))
        precondition(md.contains("- Screenshot: /tmp/p.png"))
        precondition(md.contains("display: flex;"))
        precondition(md.contains("- error: boom stack (app.js:4)"))
        precondition(md.contains("- 500 GET https://a.test/api"))

        let plain = DevHandoff.markdown(element: DevPickedElement(message: [
            "url": "u", "selector": "div", "tag": "div", "rect": [:], "html": "",
        ])!, errors: [], failed: [], imagePath: nil)
        precondition(!plain.contains("Console errors") && !plain.contains("Styles") && !plain.contains("Screenshot"))

        let many = (0..<30).map { DevConsoleEntry(level: "error", message: "e\($0)") }
        let ctx = DevHandoff.context(errors: many, failed: []).joined(separator: "\n")
        precondition(!ctx.contains("e9\n") && ctx.contains("e10") && ctx.contains("e29"), "last 20 only")

        var post = DevNetworkEntry(key: "p", kind: "fetch", method: "POST", url: "https://a.test/x")
        post.requestBody = "{\"a\":\"it's\"}"
        precondition(DevHandoff.markdown(network: post, pageURL: nil).contains("--data-raw '{\"a\":\"it'\\''s\"}'"))

        let before = "- main\n  - heading \"Cart\" [level 1]\n  - button \"Checkout\""
        let after = "- main\n  - heading \"Cart\" [level 1]\n  - text \"2 items\"\n  - button \"Checkout\" [disabled]"
        let diff = DevHandoff.snapshotDiff(old: before, new: after)
        precondition(diff.hasPrefix("1 lines removed, 2 added"), diff)
        precondition(diff.contains("-  - button \"Checkout\"\n") && diff.contains("+  - button \"Checkout\" [disabled]"))
        precondition(!diff.contains("heading"), "unchanged lines are left out")
        precondition(DevHandoff.snapshotDiff(old: before, new: before) == "No change since the last snapshot.")

        print("DevPickCheck passed")
    }
}
