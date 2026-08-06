import Foundation
import Combine
import SwiftUI

@MainActor
public final class PostStore: ObservableObject {
    @Published public var requests: [HTTPRequest] = []
    @Published public var selectedRequestID: UUID?
    @Published public var activeResponse: HTTPResponse?
    @Published public var isExecuting: Bool = false
    @Published public var errorMessage: String?

    @Published public var history: [HistoryItem] = []
    @Published public var selectedHistoryItemID: UUID?
    @Published public var searchQuery: String = ""

    @Published public var mcpServers: [MCPServer] = []
    @Published public var selectedMCPServerID: UUID?

    @Published public var activeTab: SidebarTab = .requests

    public let webhookServer = WebhookServer()
    private var cancellables = Set<AnyCancellable>()

    public enum SidebarTab: String, CaseIterable, Identifiable {
        case requests = "Requests"
        case webhooks = "Webhooks"
        case mcp = "MCP Server"
        case history = "History"

        public var id: String { rawValue }
        public var shortName: String {
            switch self {
            case .requests: return "Requests"
            case .webhooks: return "Webhooks"
            case .mcp: return "MCP"
            case .history: return "History"
            }
        }
        public var iconName: String {
            switch self {
            case .requests: return "network"
            case .webhooks: return "antenna.radiowaves.left.and.right"
            case .mcp: return "cpu"
            case .history: return "clock"
            }
        }
        public var description: String {
            switch self {
            case .requests: return "Build and test HTTP API endpoints"
            case .webhooks: return "Listen and inspect incoming local HTTP webhooks"
            case .mcp: return "Inspect Model Context Protocol (MCP) server tools"
            case .history: return "Filter past API execution logs and response headers"
            }
        }
    }

    public init() {
        seedSampleData()

        webhookServer.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        webhookServer.onPayloadReceived = { [weak self] payload in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let historyItem = HistoryItem(
                    type: .webhook,
                    title: "\(payload.method) \(payload.path)",
                    subtitle: payload.clientIP,
                    method: payload.method,
                    statusCode: 200,
                    timestamp: payload.timestamp,
                    webhookData: payload
                )
                self.history.insert(historyItem, at: 0)
            }
        }
    }

    public var selectedRequest: HTTPRequest? {
        get {
            requests.first(where: { $0.id == selectedRequestID })
        }
        set {
            if let updated = newValue, let idx = requests.firstIndex(where: { $0.id == updated.id }) {
                requests[idx] = updated
            }
        }
    }

    public var selectedHistoryItem: HistoryItem? {
        get {
            history.first(where: { $0.id == selectedHistoryItemID })
        }
        set {
            selectedHistoryItemID = newValue?.id
        }
    }

    public var filteredRequests: [HTTPRequest] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return requests
        }
        let query = searchQuery.lowercased()
        return requests.filter { req in
            req.name.lowercased().contains(query) ||
            req.url.lowercased().contains(query) ||
            req.method.rawValue.lowercased().contains(query)
        }
    }

    public var filteredHistory: [HistoryItem] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return history
        }
        let query = searchQuery.lowercased()

        // Support tokenized matching like method:POST status:200
        if query.contains(":") {
            let tokens = query.split(separator: " ")
            return history.filter { item in
                for token in tokens {
                    let parts = token.split(separator: ":")
                    if parts.count == 2 {
                        let key = String(parts[0])
                        let val = String(parts[1])
                        if key == "method" && !item.method.lowercased().contains(val) { return false }
                        if key == "status", let code = item.statusCode, !String(code).contains(val) { return false }
                        if key == "type" && !item.type.rawValue.lowercased().contains(val) { return false }
                    }
                }
                return true
            }
        }

        return history.filter { item in
            item.title.lowercased().contains(query) ||
            item.subtitle.lowercased().contains(query) ||
            item.method.lowercased().contains(query)
        }
    }

    public func createNewRequest(method: HTTPMethod = .get, name: String = "New Request", url: String = "https://httpbin.org/get") {
        let req = HTTPRequest(name: name, method: method, url: url)
        requests.append(req)
        selectedRequestID = req.id
        activeResponse = nil
    }

    public func deleteRequest(id: UUID) {
        requests.removeAll(where: { $0.id == id })
        if selectedRequestID == id {
            selectedRequestID = requests.first?.id
            activeResponse = nil
        }
    }

    public func executeSelectedRequest() async {
        guard let request = selectedRequest else { return }
        isExecuting = true
        errorMessage = nil

        do {
            let response = try await HTTPClient.shared.execute(request: request)
            activeResponse = response

            let historyItem = HistoryItem(
                type: .httpRequest,
                title: request.name.isEmpty ? request.url : request.name,
                subtitle: request.url,
                method: request.method.rawValue,
                statusCode: response.statusCode,
                durationMs: response.responseTimeMs,
                timestamp: response.timestamp,
                requestData: request,
                responseData: response
            )
            history.insert(historyItem, at: 0)
        } catch {
            errorMessage = error.localizedDescription
            activeResponse = HTTPResponse(
                requestId: request.id,
                statusCode: 0,
                statusText: "Request Failed",
                bodyText: "Error: \(error.localizedDescription)",
                responseTimeMs: 0,
                responseSizeBytes: 0,
                timestamp: Date()
            )
        }

        isExecuting = false
    }

    public func importCURL(curlCommand: String) {
        if let parsed = CURLParser.parse(curlCommand: curlCommand) {
            requests.append(parsed)
            selectedRequestID = parsed.id
            activeResponse = nil
        }
    }

    private func seedSampleData() {
        let req1 = HTTPRequest(
            name: "Get User Info",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/users/1",
            headers: [KeyValueItem(key: "User-Agent", value: "Post-Mac/1.0", isEnabled: true)]
        )
        let req2 = HTTPRequest(
            name: "Create Webhook Event",
            method: .post,
            url: "https://jsonplaceholder.typicode.com/posts",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"title\": \"user.updated\",\n  \"userId\": 123\n}"
        )
        let req3 = HTTPRequest(
            name: "Get Sample Todo",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/todos/1",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)]
        )

        requests = [req1, req2, req3]
        selectedRequestID = req1.id

        let tool1 = MCPToolInfo(
            name: "get_system_health",
            description: "Retrieve CPU, RAM, temperature, and uptime metrics for router node.",
            inputSchemaJSON: "{\n  \"verbose\": true\n}"
        )
        let tool2 = MCPToolInfo(
            name: "list_dhcp_leases",
            description: "List all active client DHCP leases on the local subnet.",
            inputSchemaJSON: "{\n  \"interface\": \"br-lan\"\n}"
        )
        let tool3 = MCPToolInfo(
            name: "get_disk_space",
            description: "Inspect filesystem disk space usage across mounted volumes.",
            inputSchemaJSON: "{\n  \"volume\": \"/\"\n}"
        )

        let server1 = MCPServer(
            name: "Router MCP Server",
            endpoint: "http://localhost:8000/sse",
            type: .sse,
            tools: [tool1, tool2],
            isConnected: true
        )
        let server2 = MCPServer(
            name: "System Helper MCP",
            endpoint: "http://localhost:8080/sse",
            type: .sse,
            tools: [tool3],
            isConnected: false
        )

        mcpServers = [server1, server2]
        selectedMCPServerID = server1.id
    }
}
