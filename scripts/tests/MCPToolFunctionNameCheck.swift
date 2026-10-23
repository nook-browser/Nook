import Foundation

@main
struct MCPToolFunctionNameCheck {
    static func main() {
        let first = MCPTool(serverId: "server.with.dots", name: "lookup.record", description: "first")
        let second = MCPTool(serverId: "server", name: "with.dots.lookup.record", description: "second")

        var registry = MCPToolFunctionRegistry()
        let firstName = registry.register(first)
        let secondName = registry.register(second)

        precondition(firstName != secondName)
        precondition(firstName.hasPrefix("mcp_lookup_record_"))
        precondition(secondName.hasPrefix("mcp_with_dots_lookup_record_"))
        precondition(isValidProviderName(firstName))
        precondition(isValidProviderName(secondName))
        precondition(registry.toolsByFunctionName[firstName]?.serverId == first.serverId)
        precondition(registry.toolsByFunctionName[firstName]?.name == first.name)
        precondition(registry.toolsByFunctionName[secondName]?.serverId == second.serverId)
        precondition(registry.toolsByFunctionName[secondName]?.name == second.name)
        precondition(first.qualifiedName == "server.with.dots.lookup.record")
        precondition(!isValidProviderName(first.qualifiedName))

        let longName = MCPTool(
            serverId: "server-\(String(repeating: "x", count: 80))",
            name: String(repeating: "y", count: 160),
            description: "long names still get a bounded alias"
        )
        let longAlias = longName.providerFunctionName()
        precondition(longAlias.count <= 64)
        precondition(isValidProviderName(longAlias))

        let naturalCollision = first.providerFunctionName()
        let avoidedAlias = first.providerFunctionName(avoiding: [naturalCollision])
        precondition(avoidedAlias != naturalCollision)
        precondition(isValidProviderName(avoidedAlias))

        var reservedRegistry = MCPToolFunctionRegistry()
        let registeredAlias = reservedRegistry.register(first, avoiding: [naturalCollision])
        precondition(registeredAlias == avoidedAlias)
        precondition(reservedRegistry.toolsByFunctionName[registeredAlias]?.name == first.name)

        var sameName = MCPToolFunctionRegistry()
        let a = sameName.register(MCPTool(serverId: "A", name: "search", description: ""))
        let b = sameName.register(MCPTool(serverId: "B", name: "search", description: ""))
        precondition(a != b && sameName.toolsByFunctionName.count == 2)
        precondition(MCPTool(serverId: "A", name: "search", description: "").providerFunctionName() == a)

        print("MCP provider function-name checks passed")
    }

    private static func isValidProviderName(_ name: String) -> Bool {
        name.count <= 64 && name.range(of: "^[a-zA-Z_][a-zA-Z0-9_-]*$", options: .regularExpression) != nil
    }
}
