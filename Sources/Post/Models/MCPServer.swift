import Foundation

public enum MCPServerType: String, Codable, CaseIterable, Identifiable, Sendable {
    case sse = "HTTP / SSE"
    case stdio = "Stdio Command"

    public var id: String { rawValue }
}

public struct MCPPropertyField: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var description: String
    public var isRequired: Bool
    public var defaultValue: String

    public init(
        name: String,
        type: String = "string",
        description: String = "",
        isRequired: Bool = false,
        defaultValue: String = ""
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
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

    public var schemaFields: [MCPPropertyField] {
        guard let data = inputSchemaJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let props = json["properties"] as? [String: [String: Any]] {
            let requiredList = (json["required"] as? [String]) ?? []
            return props.map { key, dict in
                let type = dict["type"] as? String ?? "string"
                let desc = dict["description"] as? String ?? ""
                let isReq = requiredList.contains(key)
                var defVal = ""
                if let def = dict["default"] {
                    defVal = String(describing: def)
                }
                return MCPPropertyField(name: key, type: type, description: desc, isRequired: isReq, defaultValue: defVal)
            }.sorted { $0.name < $1.name }
        } else if let props = json["properties"] as? [String: Any] {
            let requiredList = (json["required"] as? [String]) ?? []
            var fields: [MCPPropertyField] = []
            for (key, val) in props {
                if let dict = val as? [String: Any] {
                    let type = dict["type"] as? String ?? "string"
                    let desc = dict["description"] as? String ?? ""
                    let isReq = requiredList.contains(key)
                    var defVal = ""
                    if let def = dict["default"] {
                        defVal = String(describing: def)
                    }
                    fields.append(MCPPropertyField(name: key, type: type, description: desc, isRequired: isReq, defaultValue: defVal))
                }
            }
            return fields.sorted { $0.name < $1.name }
        } else {
            var fields: [MCPPropertyField] = []
            for (key, val) in json {
                if key == "$schema" || key == "type" || key == "required" { continue }
                let type: String
                if CFGetTypeID(val as CFTypeRef) == CFBooleanGetTypeID() {
                    type = "boolean"
                } else if let num = val as? NSNumber {
                    if CFNumberIsFloatType(num as CFNumber) {
                        type = "number"
                    } else {
                        type = "integer"
                    }
                } else {
                    type = "string"
                }
                fields.append(MCPPropertyField(name: key, type: type, description: "", isRequired: false, defaultValue: String(describing: val)))
            }
            return fields.sorted { $0.name < $1.name }
        }
    }
}

public struct MCPResourceInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { uri }
    public var uri: String
    public var name: String
    public var description: String
    public var mimeType: String

    public init(uri: String, name: String, description: String = "", mimeType: String = "application/json") {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

public struct MCPPromptInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var description: String

    public init(name: String, description: String = "") {
        self.name = name
        self.description = description
    }
}

public struct MCPServer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: String
    public var type: MCPServerType
    public var tools: [MCPToolInfo]
    public var resources: [MCPResourceInfo]
    public var prompts: [MCPPromptInfo]
    public var envVars: [KeyValueItem]
    public var isConnected: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Local MCP Server",
        endpoint: String = "http://localhost:8000/sse",
        type: MCPServerType = .sse,
        tools: [MCPToolInfo] = [],
        resources: [MCPResourceInfo] = [],
        prompts: [MCPPromptInfo] = [],
        envVars: [KeyValueItem] = [],
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.type = type
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
        self.envVars = envVars
        self.isConnected = isConnected
    }

    enum CodingKeys: CodingKey {
        case id, name, endpoint, type, tools, resources, prompts, envVars, isConnected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Local MCP Server"
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        type = try container.decodeIfPresent(MCPServerType.self, forKey: .type) ?? .sse
        tools = try container.decodeIfPresent([MCPToolInfo].self, forKey: .tools) ?? []
        resources = try container.decodeIfPresent([MCPResourceInfo].self, forKey: .resources) ?? []
        prompts = try container.decodeIfPresent([MCPPromptInfo].self, forKey: .prompts) ?? []
        envVars = try container.decodeIfPresent([KeyValueItem].self, forKey: .envVars) ?? []
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(type, forKey: .type)
        try container.encode(tools, forKey: .tools)
        try container.encode(resources, forKey: .resources)
        try container.encode(prompts, forKey: .prompts)
        try container.encode(envVars, forKey: .envVars)
        try container.encode(isConnected, forKey: .isConnected)
    }
}
