import Foundation

public final class MCPClient: Sendable {
    public static let shared = MCPClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchTools(endpoint: String) async throws -> [MCPToolInfo] {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "MCPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid MCP endpoint URL"])
        }

        let jsonRPC: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": [:]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonRPC, options: [])

        let (data, _) = try await session.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }

        var tools: [MCPToolInfo] = []
        for toolDict in toolsArray {
            let name = toolDict["name"] as? String ?? ""
            let desc = toolDict["description"] as? String ?? ""
            var schemaJSON = "{}"
            if let schemaDict = toolDict["inputSchema"] as? [String: Any],
               let schemaData = try? JSONSerialization.data(withJSONObject: schemaDict, options: [.prettyPrinted]),
               let str = String(data: schemaData, encoding: .utf8) {
                schemaJSON = str
            }

            if !name.isEmpty {
                tools.append(MCPToolInfo(name: name, description: desc, inputSchemaJSON: schemaJSON))
            }
        }

        return tools
    }

    public func callTool(endpoint: String, name: String, argumentsJSON: String) async throws -> (resultText: String, isError: Bool, durationMs: Double) {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "MCPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid MCP endpoint URL"])
        }

        var argsDict: [String: Any] = [:]
        if let data = argumentsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsDict = parsed
        }

        let jsonRPC: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int(Date().timeIntervalSince1970),
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": argsDict
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonRPC, options: [])

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, _) = try await session.data(for: request)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown MCP Error"
                return ("Error \(error["code"] ?? ""): \(msg)", true, durationMs)
            }
            if let result = json["result"] as? [String: Any] {
                if let prettyData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
                   let prettyStr = String(data: prettyData, encoding: .utf8) {
                    let isErr = result["isError"] as? Bool ?? false
                    return (prettyStr, isErr, durationMs)
                }
            }
        }

        let raw = String(decoding: data, as: UTF8.self)
        return (raw, false, durationMs)
    }
}
