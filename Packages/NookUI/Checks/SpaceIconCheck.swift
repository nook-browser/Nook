// Run: build NookDesign as a module, then swiftc -I/-L it with SpaceIconPicker.swift and this file.
@main
struct SpaceIconCheck {
    static func main() {
        for placeholder in ["", "square.grid.2x2", "house", "person.fill"] {
            precondition(SpaceIcon.isDot(placeholder), placeholder)
        }
        precondition(!SpaceIcon.isDot("star"))
        precondition(!SpaceIcon.isDot("🚀"))
        precondition(!SpaceIcon.isDot("nook.agent:0F0F0F0F-0000-0000-0000-000000000000"))
        precondition(SpaceIcon.isEmoji("🚀") && !SpaceIcon.isEmoji("star"))
        print("ok")
    }
}
