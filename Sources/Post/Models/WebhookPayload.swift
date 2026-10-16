import Foundation

public struct WebhookPayload: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var method: String
    public var path: String
    public var headers: [KeyValueItem]
    public var body: String
    public var clientIP: String
    public var responseStatusCode: Int
    public var forwardedTo: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String = "POST",
        path: String = "/webhook",
        headers: [KeyValueItem] = [],
        body: String = "",
        clientIP: String = "127.0.0.1",
        responseStatusCode: Int = 200,
        forwardedTo: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
        self.clientIP = clientIP
        self.responseStatusCode = responseStatusCode
        self.forwardedTo = forwardedTo
    }

    enum CodingKeys: CodingKey {
        case id
        case timestamp
        case method
        case path
        case headers
        case body
        case clientIP
        case responseStatusCode
        case forwardedTo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.method = try container.decodeIfPresent(String.self, forKey: .method) ?? "POST"
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? "/webhook"
        self.headers = try container.decodeIfPresent([KeyValueItem].self, forKey: .headers) ?? []
        self.body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        self.clientIP = try container.decodeIfPresent(String.self, forKey: .clientIP) ?? "127.0.0.1"
        self.responseStatusCode = try container.decodeIfPresent(Int.self, forKey: .responseStatusCode) ?? 200
        self.forwardedTo = try container.decodeIfPresent(String.self, forKey: .forwardedTo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(method, forKey: .method)
        try container.encode(path, forKey: .path)
        try container.encode(headers, forKey: .headers)
        try container.encode(body, forKey: .body)
        try container.encode(clientIP, forKey: .clientIP)
        try container.encode(responseStatusCode, forKey: .responseStatusCode)
        try container.encodeIfPresent(forwardedTo, forKey: .forwardedTo)
    }

    public var formattedBody: String {
        guard !body.isEmpty else { return "" }
        if let data = body.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return body
    }

    public func asCURL(port: UInt16 = 9090) -> String {
        var command = "curl -X \(method) \"http://localhost:\(port)\(path)\""
        for header in headers where header.isEnabled {
            let escapedVal = header.value.replacingOccurrences(of: "\"", with: "\\\"")
            command += " \\\n  -H \"\(header.key): \(escapedVal)\""
        }
        if !body.isEmpty {
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            command += " \\\n  --data '\(escapedBody)'"
        }
        return command
    }
}

public struct WebhookMockRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var pathPrefix: String
    public var statusCode: Int
    public var responseHeaders: [KeyValueItem]
    public var responseBody: String
    public var delayMs: Int
    public var forwardToURL: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Default 200 OK",
        pathPrefix: String = "/webhook",
        statusCode: Int = 200,
        responseHeaders: [KeyValueItem] = [KeyValueItem(key: "Content-Type", value: "application/json")],
        responseBody: String = "{\"status\":\"ok\"}",
        delayMs: Int = 0,
        forwardToURL: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.pathPrefix = pathPrefix
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.delayMs = delayMs
        self.forwardToURL = forwardToURL
        self.isEnabled = isEnabled
    }

    enum CodingKeys: CodingKey {
        case id
        case name
        case pathPrefix
        case statusCode
        case responseHeaders
        case responseBody
        case delayMs
        case forwardToURL
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default 200 OK"
        self.pathPrefix = try container.decodeIfPresent(String.self, forKey: .pathPrefix) ?? "/webhook"
        self.statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode) ?? 200
        self.responseHeaders = try container.decodeIfPresent([KeyValueItem].self, forKey: .responseHeaders) ?? [KeyValueItem(key: "Content-Type", value: "application/json")]
        self.responseBody = try container.decodeIfPresent(String.self, forKey: .responseBody) ?? "{\"status\":\"ok\"}"
        self.delayMs = try container.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
        self.forwardToURL = try container.decodeIfPresent(String.self, forKey: .forwardToURL) ?? ""
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(pathPrefix, forKey: .pathPrefix)
        try container.encode(statusCode, forKey: .statusCode)
        try container.encode(responseHeaders, forKey: .responseHeaders)
        try container.encode(responseBody, forKey: .responseBody)
        try container.encode(delayMs, forKey: .delayMs)
        try container.encode(forwardToURL, forKey: .forwardToURL)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}
