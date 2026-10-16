import Foundation

public final class MCPClient: Sendable {
    public static let shared = MCPClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Legacy / Backward-Compatible HTTP Methods

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
            if let schemaDict = (toolDict["inputSchema"] as? [String: Any]) ?? (toolDict["parameters"] as? [String: Any]),
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

    // MARK: - Full MCP Lifecycle & Capabilities

    public func fetchServerCapabilities(server: MCPServer) async throws -> (tools: [MCPToolInfo], resources: [MCPResourceInfo], prompts: [MCPPromptInfo]) {
        if server.type == .stdio {
            return try await fetchStdioCapabilities(server: server)
        } else {
            return try await fetchSSECapabilities(server: server)
        }
    }

    private func fetchStdioCapabilities(server: MCPServer) async throws -> (tools: [MCPToolInfo], resources: [MCPResourceInfo], prompts: [MCPPromptInfo]) {
        let stdioSession = try StdioProcessSession(command: server.endpoint, envVars: server.envVars)
        defer { stdioSession.terminate() }

        // Step 1: initialize
        stdioSession.send(json: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:],
                    "resources": [:],
                    "prompts": [:]
                ],
                "clientInfo": [
                    "name": "Post",
                    "version": "1.0.0"
                ]
            ]
        ])

        _ = await stdioSession.waitForResponse(id: "1", timeoutSeconds: 1.5)

        // Step 2: notifications/initialized
        stdioSession.send(json: [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ])

        // Step 3: tools/list, resources/list, prompts/list
        stdioSession.send(json: [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": [:]
        ])

        stdioSession.send(json: [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "resources/list",
            "params": [:]
        ])

        stdioSession.send(json: [
            "jsonrpc": "2.0",
            "id": 4,
            "method": "prompts/list",
            "params": [:]
        ])

        async let toolsWait = stdioSession.waitForResponse(id: "2", timeoutSeconds: 2.5)
        async let resourcesWait = stdioSession.waitForResponse(id: "3", timeoutSeconds: 2.5)
        async let promptsWait = stdioSession.waitForResponse(id: "4", timeoutSeconds: 2.5)

        let (toolsJSON, resourcesJSON, promptsJSON) = await (toolsWait, resourcesWait, promptsWait)

        var tools: [MCPToolInfo] = []
        if let result = toolsJSON?["result"] as? [String: Any],
           let toolsArray = result["tools"] as? [[String: Any]] {
            for toolDict in toolsArray {
                let name = toolDict["name"] as? String ?? ""
                let desc = toolDict["description"] as? String ?? ""
                var schemaJSON = "{}"
                if let schemaDict = (toolDict["inputSchema"] as? [String: Any]) ?? (toolDict["parameters"] as? [String: Any]),
                   let schemaData = try? JSONSerialization.data(withJSONObject: schemaDict, options: [.prettyPrinted]),
                   let str = String(data: schemaData, encoding: .utf8) {
                    schemaJSON = str
                }
                if !name.isEmpty {
                    tools.append(MCPToolInfo(name: name, description: desc, inputSchemaJSON: schemaJSON))
                }
            }
        }

        var resources: [MCPResourceInfo] = []
        if let result = resourcesJSON?["result"] as? [String: Any],
           let resArray = result["resources"] as? [[String: Any]] {
            for resDict in resArray {
                let uri = resDict["uri"] as? String ?? ""
                let name = resDict["name"] as? String ?? uri
                let desc = resDict["description"] as? String ?? ""
                let mime = resDict["mimeType"] as? String ?? "application/json"
                if !uri.isEmpty {
                    resources.append(MCPResourceInfo(uri: uri, name: name, description: desc, mimeType: mime))
                }
            }
        }

        var prompts: [MCPPromptInfo] = []
        if let result = promptsJSON?["result"] as? [String: Any],
           let pArray = result["prompts"] as? [[String: Any]] {
            for pDict in pArray {
                let name = pDict["name"] as? String ?? ""
                let desc = pDict["description"] as? String ?? ""
                if !name.isEmpty {
                    prompts.append(MCPPromptInfo(name: name, description: desc))
                }
            }
        }

        return (tools, resources, prompts)
    }

    private func fetchSSECapabilities(server: MCPServer) async throws -> (tools: [MCPToolInfo], resources: [MCPResourceInfo], prompts: [MCPPromptInfo]) {
        guard let url = URL(string: server.endpoint) else {
            throw NSError(domain: "MCPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid MCP endpoint URL"])
        }

        let tools = try await fetchTools(endpoint: server.endpoint)
        var resources: [MCPResourceInfo] = []
        var prompts: [MCPPromptInfo] = []

        // Try resources/list
        do {
            let resRPC: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "resources/list",
                "params": [:]
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: resRPC, options: [])
            let (data, _) = try await session.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let resArray = result["resources"] as? [[String: Any]] {
                for r in resArray {
                    let uri = r["uri"] as? String ?? ""
                    let name = r["name"] as? String ?? uri
                    let desc = r["description"] as? String ?? ""
                    let mime = r["mimeType"] as? String ?? "application/json"
                    if !uri.isEmpty {
                        resources.append(MCPResourceInfo(uri: uri, name: name, description: desc, mimeType: mime))
                    }
                }
            }
        } catch {
            // Optional capability
        }

        // Try prompts/list
        do {
            let pRPC: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "prompts/list",
                "params": [:]
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: pRPC, options: [])
            let (data, _) = try await session.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let pArray = result["prompts"] as? [[String: Any]] {
                for p in pArray {
                    let name = p["name"] as? String ?? ""
                    let desc = p["description"] as? String ?? ""
                    if !name.isEmpty {
                        prompts.append(MCPPromptInfo(name: name, description: desc))
                    }
                }
            }
        } catch {
            // Optional capability
        }

        return (tools, resources, prompts)
    }

    // MARK: - Execute Tool

    public func executeTool(server: MCPServer, name: String, argumentsJSON: String) async throws -> (resultText: String, isError: Bool, durationMs: Double) {
        if server.type == .stdio {
            let stdioSession = try StdioProcessSession(command: server.endpoint, envVars: server.envVars)
            defer { stdioSession.terminate() }

            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:],
                    "clientInfo": ["name": "Post", "version": "1.0.0"]
                ]
            ])
            _ = await stdioSession.waitForResponse(id: "1", timeoutSeconds: 1.5)

            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "method": "notifications/initialized"
            ])

            var argsDict: [String: Any] = [:]
            if let data = argumentsJSON.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                argsDict = parsed
            }

            let startTime = CFAbsoluteTimeGetCurrent()
            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": name,
                    "arguments": argsDict
                ]
            ])

            guard let response = await stdioSession.waitForResponse(id: "2", timeoutSeconds: 10.0) else {
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                return ("Error: Tool execution timed out after 10s", true, durationMs)
            }

            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            if let error = response["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown MCP Error"
                return ("Error \(error["code"] ?? ""): \(msg)", true, durationMs)
            }
            if let result = response["result"] as? [String: Any] {
                if let prettyData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
                   let prettyStr = String(data: prettyData, encoding: .utf8) {
                    let isErr = result["isError"] as? Bool ?? false
                    return (prettyStr, isErr, durationMs)
                }
            }
            return (String(describing: response), false, durationMs)
        } else {
            return try await callTool(endpoint: server.endpoint, name: name, argumentsJSON: argumentsJSON)
        }
    }

    // MARK: - Read Resource

    public func readResource(server: MCPServer, uri: String) async throws -> (content: String, durationMs: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()

        if server.type == .stdio {
            let stdioSession = try StdioProcessSession(command: server.endpoint, envVars: server.envVars)
            defer { stdioSession.terminate() }

            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:],
                    "clientInfo": ["name": "Post", "version": "1.0.0"]
                ]
            ])
            _ = await stdioSession.waitForResponse(id: "1", timeoutSeconds: 1.5)

            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "method": "notifications/initialized"
            ])

            stdioSession.send(json: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "resources/read",
                "params": ["uri": uri]
            ])

            guard let response = await stdioSession.waitForResponse(id: "2", timeoutSeconds: 5.0) else {
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                return ("Error: Resource read timed out", durationMs)
            }

            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            if let error = response["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown error"
                return ("Error \(error["code"] ?? ""): \(msg)", durationMs)
            }
            if let result = response["result"] as? [String: Any] {
                if let contents = result["contents"] as? [[String: Any]],
                   let first = contents.first,
                   let text = first["text"] as? String {
                    return (text, durationMs)
                }
                if let prettyData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
                   let str = String(data: prettyData, encoding: .utf8) {
                    return (str, durationMs)
                }
            }
            return (String(describing: response), durationMs)
        } else {
            guard let url = URL(string: server.endpoint) else {
                throw NSError(domain: "MCPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid MCP endpoint URL"])
            }
            let jsonRPC: [String: Any] = [
                "jsonrpc": "2.0",
                "id": Int(Date().timeIntervalSince1970),
                "method": "resources/read",
                "params": ["uri": uri]
            ]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonRPC, options: [])

            let (data, _) = try await session.data(for: request)
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? [String: Any] {
                    let msg = error["message"] as? String ?? "Unknown error"
                    return ("Error \(error["code"] ?? ""): \(msg)", durationMs)
                }
                if let result = json["result"] as? [String: Any] {
                    if let contents = result["contents"] as? [[String: Any]],
                       let first = contents.first,
                       let text = first["text"] as? String {
                        return (text, durationMs)
                    }
                    if let prettyData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
                       let str = String(data: prettyData, encoding: .utf8) {
                        return (str, durationMs)
                    }
                }
            }
            return (String(decoding: data, as: UTF8.self), durationMs)
        }
    }

    // MARK: - Discover Local Configured Servers

    public func discoverLocalConfiguredServers() -> [MCPServer] {
        var discoveredServers: [MCPServer] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // 1. Scan standard MCP config files
        let configPaths = [
            "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
            "\(home)/.cursor/mcp.json"
        ]

        for path in configPaths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let serversDict = json["mcpServers"] as? [String: [String: Any]] else {
                continue
            }

            for (serverName, sDict) in serversDict {
                let command = sDict["command"] as? String ?? ""
                let args = (sDict["args"] as? [String]) ?? []
                let url = sDict["url"] as? String ?? sDict["endpoint"] as? String
                let envDict = (sDict["env"] as? [String: String]) ?? [:]

                let envItems = envDict.map { KeyValueItem(key: $0.key, value: $0.value, isEnabled: true) }

                let type: MCPServerType
                let endpoint: String

                if let url = url, !url.isEmpty {
                    type = .sse
                    endpoint = url
                } else {
                    type = .stdio
                    endpoint = args.isEmpty ? command : ([command] + args).joined(separator: " ")
                }

                if !discoveredServers.contains(where: { $0.name.lowercased() == serverName.lowercased() }) {
                    let server = MCPServer(
                        name: serverName,
                        endpoint: endpoint,
                        type: type,
                        tools: [],
                        resources: [],
                        prompts: [],
                        envVars: envItems,
                        isConnected: false
                    )
                    discoveredServers.append(server)
                }
            }
        }

        // 2. Scan ~/.gemini/antigravity-cli/mcp/
        let mcpDir = "\(home)/.gemini/antigravity-cli/mcp"
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: mcpDir) {
            for subdir in subdirs {
                let serverPath = "\(mcpDir)/\(subdir)"
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: serverPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let files = (try? FileManager.default.contentsOfDirectory(atPath: serverPath)) ?? []
                var tools: [MCPToolInfo] = []
                var resources: [MCPResourceInfo] = []

                for file in files {
                    if file.hasSuffix(".json") {
                        let filePath = "\(serverPath)/\(file)"
                        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        let toolName = dict["name"] as? String ?? file.replacingOccurrences(of: ".json", with: "")
                        let desc = dict["description"] as? String ?? ""
                        var schemaStr = "{}"
                        if let params = (dict["parameters"] as? [String: Any]) ?? (dict["inputSchema"] as? [String: Any]),
                           let sData = try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted]),
                           let s = String(data: sData, encoding: .utf8) {
                            schemaStr = s
                        }
                        tools.append(MCPToolInfo(name: toolName, description: desc, inputSchemaJSON: schemaStr))
                    } else if file == "instructions.md" {
                        let filePath = "\(serverPath)/\(file)"
                        resources.append(
                            MCPResourceInfo(
                                uri: "file://\(filePath)",
                                name: "Server Guide & References",
                                description: "Detailed documentation and instructions for \(subdir)",
                                mimeType: "text/markdown"
                            )
                        )
                    }
                }

                tools.sort { $0.name < $1.name }

                // Check if already in discoveredServers by name or partial match
                let matchIndex = discoveredServers.firstIndex { s in
                    let sName = s.name.lowercased()
                    let dName = subdir.lowercased()
                    return sName == dName ||
                           (dName == "ha-mcp" && sName.contains("home assistant")) ||
                           (dName == "homeassistant" && sName.contains("home assistant"))
                }

                if let idx = matchIndex {
                    if !tools.isEmpty {
                        discoveredServers[idx].tools = tools
                    }
                    if !resources.isEmpty {
                        discoveredServers[idx].resources.append(contentsOf: resources)
                    }
                } else {
                    let defaultCmd: String
                    if subdir == "ha-mcp" {
                        defaultCmd = "uvx ha-mcp@latest"
                    } else {
                        defaultCmd = "npx -y \(subdir)"
                    }
                    let newServer = MCPServer(
                        name: subdir,
                        endpoint: defaultCmd,
                        type: .stdio,
                        tools: tools,
                        resources: resources,
                        prompts: [],
                        envVars: [],
                        isConnected: false
                    )
                    discoveredServers.append(newServer)
                }
            }
        }

        return discoveredServers
    }
}

// MARK: - Stdio Process Session Support

private final class StdioProcessSession: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [String: Data] = [:]
    private var waiters: [UUID: (id: String, continuation: CheckedContinuation<Data?, Never>)] = [:]

    init(command: String, envVars: [KeyValueItem]) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        let standardPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = currentPath.isEmpty ? standardPaths : "\(currentPath):\(standardPaths)"

        for item in envVars where item.isEnabled && !item.key.isEmpty {
            env[item.key] = item.value
        }

        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        setupStdoutReader()
        try process.run()
    }

    private func setupStdoutReader() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            self.lock.lock()
            self.buffer.append(data)

            while let newlineIndex = self.buffer.firstIndex(of: 0x0A) {
                let lineData = self.buffer.subdata(in: 0..<newlineIndex)
                self.buffer.removeSubrange(0...newlineIndex)

                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    let idKey: String?
                    if let intId = json["id"] as? Int {
                        idKey = String(intId)
                    } else if let strId = json["id"] as? String {
                        idKey = strId
                    } else {
                        idKey = nil
                    }

                    if let id = idKey {
                        self.responses[id] = lineData
                        var toResume: [CheckedContinuation<Data?, Never>] = []
                        for (wid, waiter) in self.waiters where waiter.id == id {
                            self.waiters.removeValue(forKey: wid)
                            toResume.append(waiter.continuation)
                        }
                        self.lock.unlock()
                        for cont in toResume {
                            cont.resume(returning: lineData)
                        }
                        self.lock.lock()
                    }
                }
            }
            self.lock.unlock()
        }
    }

    func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else { return }
        var packet = data
        packet.append(0x0A)
        try? stdinPipe.fileHandleForWriting.write(contentsOf: packet)
    }

    private func existingResponseOrRegisterWaiter(id: String, waiterID: UUID, continuation: CheckedContinuation<Data?, Never>) -> Data? {
        lock.withLock {
            if let existing = responses[id] {
                return existing
            }
            waiters[waiterID] = (id, continuation)
            return nil
        }
    }

    private func removeTimedOutWaiter(waiterID: UUID) -> CheckedContinuation<Data?, Never>? {
        lock.withLock {
            waiters.removeValue(forKey: waiterID)?.continuation
        }
    }

    func waitForResponse(id: String, timeoutSeconds: Double) async -> [String: Any]? {
        let waiterID = UUID()
        let responseData: Data? = await withCheckedContinuation { continuation in
            if let existing = existingResponseOrRegisterWaiter(id: id, waiterID: waiterID, continuation: continuation) {
                continuation.resume(returning: existing)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let cont = self.removeTimedOutWaiter(waiterID: waiterID) {
                    cont.resume(returning: nil)
                }
            }
        }
        guard let data = responseData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func terminate() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        lock.lock()
        let pending = waiters.values.map { $0.continuation }
        waiters.removeAll()
        lock.unlock()
        for cont in pending {
            cont.resume(returning: nil)
        }
    }
}
