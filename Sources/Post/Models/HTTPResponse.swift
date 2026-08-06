import Foundation

public struct HTTPResponse: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var requestId: UUID?
    public var statusCode: Int
    public var statusText: String
    public var headers: [KeyValueItem]
    public var bodyText: String
    public var responseTimeMs: Double
    public var responseSizeBytes: Int64
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        requestId: UUID? = nil,
        statusCode: Int = 200,
        statusText: String = "OK",
        headers: [KeyValueItem] = [],
        bodyText: String = "",
        responseTimeMs: Double = 0.0,
        responseSizeBytes: Int64 = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.requestId = requestId
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.bodyText = bodyText
        self.responseTimeMs = responseTimeMs
        self.responseSizeBytes = responseSizeBytes
        self.timestamp = timestamp
    }

    public var isSuccess: Bool {
        return statusCode >= 200 && statusCode < 300
    }

    public var formattedBody: String {
        guard !bodyText.isEmpty else { return "" }
        if let data = bodyText.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return bodyText
    }
}
