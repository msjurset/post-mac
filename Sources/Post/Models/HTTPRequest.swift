import Foundation

public enum HTTPMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"

    public var id: String { rawValue }
    
    public var badgeColor: String {
        switch self {
        case .get: return "blue"
        case .post: return "green"
        case .put: return "orange"
        case .delete: return "red"
        case .patch: return "purple"
        case .head, .options: return "gray"
        }
    }
}

public struct KeyValueItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), key: String = "", value: String = "", isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

public enum BodyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case json = "JSON"
    case formData = "Form Data"
    case raw = "Raw Text"

    public var id: String { rawValue }
}

public struct HTTPRequest: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var method: HTTPMethod
    public var url: String
    public var headers: [KeyValueItem]
    public var queryParams: [KeyValueItem]
    public var bodyType: BodyType
    public var bodyText: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "New Request",
        method: HTTPMethod = .get,
        url: String = "https://httpbin.org/get",
        headers: [KeyValueItem] = [
            KeyValueItem(key: "User-Agent", value: "Post-Mac/1.0", isEnabled: true),
            KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)
        ],
        queryParams: [KeyValueItem] = [],
        bodyType: BodyType = .none,
        bodyText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.headers = headers
        self.queryParams = queryParams
        self.bodyType = bodyType
        self.bodyText = bodyText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Construct full URL with query parameters appended
    public var fullURL: URL? {
        guard var components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return URL(string: url)
        }
        let activeParams = queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        if !activeParams.isEmpty {
            var existingItems = components.queryItems ?? []
            for param in activeParams {
                existingItems.append(URLQueryItem(name: param.key, value: param.value))
            }
            components.queryItems = existingItems
        }
        return components.url
    }
}
