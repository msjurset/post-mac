import Foundation

public enum MCPServerType: String, Codable, CaseIterable, Identifiable, Sendable {
    case sse = "HTTP / SSE"
    case stdio = "Stdio Command"

    public var id: String { rawValue }
}

public struct MCPToolInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchemaJSON: String

    public init(name: String, description: String = "", inputSchemaJSON: String = "{}") {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }
}

public struct MCPServer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: String
    public var type: MCPServerType
    public var tools: [MCPToolInfo]
    public var isConnected: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Local MCP Server",
        endpoint: String = "http://localhost:8000/sse",
        type: MCPServerType = .sse,
        tools: [MCPToolInfo] = [],
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.type = type
        self.tools = tools
        self.isConnected = isConnected
    }
}
