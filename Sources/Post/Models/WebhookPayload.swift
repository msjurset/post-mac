import Foundation

public struct WebhookPayload: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var method: String
    public var path: String
    public var headers: [KeyValueItem]
    public var body: String
    public var clientIP: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String = "POST",
        path: String = "/webhook",
        headers: [KeyValueItem] = [],
        body: String = "",
        clientIP: String = "127.0.0.1"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
        self.clientIP = clientIP
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
}
