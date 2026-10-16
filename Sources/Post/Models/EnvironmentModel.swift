import Foundation

public enum AuthType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case bearer = "Bearer Token"
    case basic = "Basic Auth"
    case apiKey = "API Key"

    public var id: String { rawValue }
}

public enum APIKeyLocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case header = "Header"
    case query = "Query Param"

    public var id: String { rawValue }
}

public struct AuthConfig: Codable, Hashable, Sendable {
    public var type: AuthType
    public var bearerToken: String
    public var basicUsername: String
    public var basicPassword: String
    public var apiKeyName: String
    public var apiKeyValue: String
    public var apiKeyLocation: APIKeyLocation

    public init(
        type: AuthType = .none,
        bearerToken: String = "",
        basicUsername: String = "",
        basicPassword: String = "",
        apiKeyName: String = "X-API-Key",
        apiKeyValue: String = "",
        apiKeyLocation: APIKeyLocation = .header
    ) {
        self.type = type
        self.bearerToken = bearerToken
        self.basicUsername = basicUsername
        self.basicPassword = basicPassword
        self.apiKeyName = apiKeyName
        self.apiKeyValue = apiKeyValue
        self.apiKeyLocation = apiKeyLocation
    }

    enum CodingKeys: CodingKey {
        case type, bearerToken, basicUsername, basicPassword, apiKeyName, apiKeyValue, apiKeyLocation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(AuthType.self, forKey: .type) ?? .none
        self.bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        self.basicUsername = try container.decodeIfPresent(String.self, forKey: .basicUsername) ?? ""
        self.basicPassword = try container.decodeIfPresent(String.self, forKey: .basicPassword) ?? ""
        self.apiKeyName = try container.decodeIfPresent(String.self, forKey: .apiKeyName) ?? "X-API-Key"
        self.apiKeyValue = try container.decodeIfPresent(String.self, forKey: .apiKeyValue) ?? ""
        self.apiKeyLocation = try container.decodeIfPresent(APIKeyLocation.self, forKey: .apiKeyLocation) ?? .header
    }
}

public struct ResponseExtractionRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var jsonPath: String
    public var targetVariable: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        jsonPath: String = "",
        targetVariable: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.jsonPath = jsonPath
        self.targetVariable = targetVariable
        self.isEnabled = isEnabled
    }

    enum CodingKeys: CodingKey {
        case id, jsonPath, targetVariable, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.jsonPath = try container.decodeIfPresent(String.self, forKey: .jsonPath) ?? ""
        self.targetVariable = try container.decodeIfPresent(String.self, forKey: .targetVariable) ?? ""
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct EnvironmentVariable: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isSecret: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isSecret: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
    }

    enum CodingKeys: CodingKey {
        case id, key, value, isSecret, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        self.value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        self.isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct PostEnvironment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var variables: [EnvironmentVariable]

    public init(
        id: UUID = UUID(),
        name: String = "Local",
        variables: [EnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.variables = variables
    }

    enum CodingKeys: CodingKey {
        case id, name, variables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Local"
        self.variables = try container.decodeIfPresent([EnvironmentVariable].self, forKey: .variables) ?? []
    }
}

public struct RequestCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var iconName: String

    public init(
        id: UUID = UUID(),
        name: String = "General",
        iconName: String = "folder"
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
    }

    enum CodingKeys: CodingKey {
        case id, name, iconName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "General"
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "folder"
    }
}
