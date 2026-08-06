import Foundation

public enum HistoryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case httpRequest = "HTTP"
    case webhook = "Webhook"
    case mcp = "MCP"

    public var id: String { rawValue }
}

public struct HistoryItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: HistoryType
    public var title: String
    public var subtitle: String
    public var method: String
    public var statusCode: Int?
    public var durationMs: Double?
    public var timestamp: Date
    public var requestData: HTTPRequest?
    public var responseData: HTTPResponse?
    public var webhookData: WebhookPayload?

    public init(
        id: UUID = UUID(),
        type: HistoryType = .httpRequest,
        title: String = "",
        subtitle: String = "",
        method: String = "GET",
        statusCode: Int? = 200,
        durationMs: Double? = nil,
        timestamp: Date = Date(),
        requestData: HTTPRequest? = nil,
        responseData: HTTPResponse? = nil,
        webhookData: WebhookPayload? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.method = method
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.requestData = requestData
        self.responseData = responseData
        self.webhookData = webhookData
    }
}
