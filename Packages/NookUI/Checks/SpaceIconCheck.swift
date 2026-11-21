// Licensed under GPL-3.0. See LICENSE.
// NookDesign is built as a module beside the binary, then linked in:
//
//   D=Packages/NookDesign/Sources/NookDesign; mkdir -p /tmp/x-lib
//   swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -module-name NookDesign \
//          -module-link-name NookDesign $D/*.swift -emit-module-path /tmp/x-lib/NookDesign.swiftmodule \
//          -o /tmp/x-lib/libNookDesign.dylib && \
//   swiftc -swift-version 5 -I /tmp/x-lib -L /tmp/x-lib -lNookDesign -Xlinker -rpath -Xlinker /tmp/x-lib \
//          Packages/NookUI/Sources/NookUI/Spaces/SpaceIconPicker.swift Packages/NookUI/Checks/SpaceIconCheck.swift -o /tmp/x && /tmp/x
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
