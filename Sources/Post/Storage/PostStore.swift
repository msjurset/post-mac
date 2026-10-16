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

    @Published public var environments: [PostEnvironment] = []
    @Published public var selectedEnvironmentID: UUID?
    @Published public var collections: [RequestCollection] = []
    @Published public var selectedCollectionID: UUID?
    @Published public var focusSearchTrigger: Int = 0
    @Published public var showingEnvironmentSheet: Bool = false
    @Published public var showingSettingsSheet: Bool = false

    @Published public var enableSlashCommands: Bool = UserDefaults.standard.object(forKey: "post.enableSlashCommands") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enableSlashCommands, forKey: "post.enableSlashCommands")
        }
    }

    @Published public var enableVimEditor: Bool = UserDefaults.standard.object(forKey: "post.enableVimEditor") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enableVimEditor, forKey: "post.enableVimEditor")
        }
    }

    @Published public var enableSyntaxHighlighting: Bool = UserDefaults.standard.object(forKey: "post.enableSyntaxHighlighting") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enableSyntaxHighlighting, forKey: "post.enableSyntaxHighlighting")
        }
    }

    public let webhookServer = WebhookServer()
    private var cancellables = Set<AnyCancellable>()

    private let storageURL: URL
    private let persistenceEnabled: Bool

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

    public static func live() -> PostStore {
        PostStore(loadFromDisk: true)
    }

    public init(storageURL: URL? = nil, loadFromDisk: Bool = false) {
        let resolvedURL = storageURL ?? Self.defaultStorageURL()
        self.storageURL = resolvedURL
        self.persistenceEnabled = loadFromDisk || storageURL != nil

        if loadFromDisk {
            let loaded = loadWorkspaceFromDisk()
            if !loaded || (resolvedURL == Self.defaultStorageURL() && requests.count <= 4) {
                seedSampleData()
                saveToDisk()
            } else if webhookServer.payloads.isEmpty && history.isEmpty {
                seedSampleRuntimeHistoryAndWebhooks(primaryRequest: requests.first)
            }
        } else {
            seedSampleData()
        }

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

        if persistenceEnabled {
            $requests.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
            $environments.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
            $collections.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
            $mcpServers.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
            $selectedEnvironmentID.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
            $selectedCollectionID.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] _ in self?.saveToDisk() }.store(in: &cancellables)
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

    public var activeEnvironment: PostEnvironment? {
        environments.first(where: { $0.id == selectedEnvironmentID })
    }

    public var filteredRequests: [HTTPRequest] {
        let filter = SearchFilter(query: searchQuery)
        var list = requests

        if filter.collections.isEmpty {
            if let colId = selectedCollectionID {
                list = list.filter { $0.collectionId == colId }
            }
        }

        if filter.isEmpty {
            return list
        }

        return list.filter { req in
            for m in filter.methods {
                if !req.method.rawValue.lowercased().contains(m) { return false }
            }
            for h in filter.hosts {
                let full = req.url.lowercased()
                if let url = URL(string: req.url), let host = url.host?.lowercased() {
                    if !host.contains(h) && !full.contains(h) { return false }
                } else if !full.contains(h) {
                    return false
                }
            }
            for c in filter.collections {
                if let colId = req.collectionId, let col = collections.first(where: { $0.id == colId }) {
                    if !col.name.lowercased().contains(c) { return false }
                } else {
                    return false
                }
            }
            for text in filter.freeTexts {
                let inName = req.name.lowercased().contains(text)
                let inURL = req.url.lowercased().contains(text)
                let inMethod = req.method.rawValue.lowercased().contains(text)
                let inBody = req.bodyText.lowercased().contains(text)
                if !inName && !inURL && !inMethod && !inBody { return false }
            }
            return true
        }
    }

    public var filteredHistory: [HistoryItem] {
        let filter = SearchFilter(query: searchQuery)
        if filter.isEmpty {
            return history
        }

        return history.filter { item in
            for m in filter.methods {
                if !item.method.lowercased().contains(m) { return false }
            }
            for s in filter.statuses {
                if let code = item.statusCode {
                    if !String(code).contains(s) { return false }
                } else {
                    return false
                }
            }
            for t in filter.types {
                if !item.type.rawValue.lowercased().contains(t) { return false }
            }
            for h in filter.hosts {
                let target = (item.requestData?.url ?? item.subtitle).lowercased()
                if !target.contains(h) { return false }
            }
            for c in filter.collections {
                if let colId = item.requestData?.collectionId, let col = collections.first(where: { $0.id == colId }) {
                    if !col.name.lowercased().contains(c) { return false }
                } else {
                    return false
                }
            }
            for text in filter.freeTexts {
                let inTitle = item.title.lowercased().contains(text)
                let inSub = item.subtitle.lowercased().contains(text)
                let inMethod = item.method.lowercased().contains(text)
                let inBody = (item.requestData?.bodyText ?? "").lowercased().contains(text)
                let inResp = (item.responseData?.bodyText ?? "").lowercased().contains(text)
                if !inTitle && !inSub && !inMethod && !inBody && !inResp { return false }
            }
            return true
        }
    }

    public func createNewRequest(
        method: HTTPMethod = .get,
        name: String = "New Request",
        url: String = "https://httpbin.org/get",
        collectionId: UUID? = nil
    ) {
        let targetColId = collectionId ?? selectedCollectionID
        let req = HTTPRequest(name: name, method: method, url: url, collectionId: targetColId)
        requests.append(req)
        selectedRequestID = req.id
        activeResponse = nil
        saveToDisk()
    }

    public func deleteRequest(id: UUID) {
        requests.removeAll(where: { $0.id == id })
        if selectedRequestID == id {
            selectedRequestID = requests.first?.id
            activeResponse = nil
        }
        saveToDisk()
    }

    public func activeEnvironmentVariables() -> [String: String] {
        var dict: [String: String] = [:]

        func resolveValue(for variable: EnvironmentVariable) -> String {
            let rawVal: String
            if variable.isSecret {
                rawVal = KeychainHelper.shared.getSecret(forKey: variable.key) ?? variable.value
            } else {
                rawVal = variable.value
            }
            if KeychainHelper.isOnePasswordReference(rawVal) {
                return KeychainHelper.shared.resolveOnePasswordReference(rawVal) ?? rawVal
            }
            return rawVal
        }

        // Populate fallback variables from non-selected environments for unique keys (e.g. ha_url)
        for env in environments where env.id != selectedEnvironmentID {
            for variable in env.variables where variable.isEnabled && !variable.key.isEmpty {
                if dict[variable.key] == nil {
                    dict[variable.key] = resolveValue(for: variable)
                }
            }
        }

        // Active environment variables always take precedence
        if let envId = selectedEnvironmentID,
           let activeEnv = environments.first(where: { $0.id == envId }) {
            for variable in activeEnv.variables where variable.isEnabled && !variable.key.isEmpty {
                dict[variable.key] = resolveValue(for: variable)
            }
        }
        return dict
    }

    public func interpolate(_ input: String) -> String {
        guard input.contains("{{") else { return input }
        let vars = activeEnvironmentVariables()
        var result = input
        for (key, val) in vars {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: val)
            result = result.replacingOccurrences(of: "{{ \(key) }}", with: val)
        }
        if let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}") {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let keyRange = match.range(at: 1)
                    let key = nsString.substring(with: keyRange).trimmingCharacters(in: .whitespaces)
                    if let val = vars[key] {
                        let fullRange = match.range(at: 0)
                        result = (result as NSString).replacingCharacters(in: fullRange, with: val)
                    } else if KeychainHelper.isOnePasswordReference(key),
                              let resolved = KeychainHelper.shared.resolveOnePasswordReference(key) {
                        let fullRange = match.range(at: 0)
                        result = (result as NSString).replacingCharacters(in: fullRange, with: resolved)
                    }
                }
            }
        }
        return result
    }

    public func resolvedRequest(_ request: HTTPRequest) -> HTTPRequest {
        var resolved = request
        resolved.url = interpolate(request.url)
        resolved.bodyText = interpolate(request.bodyText)
        resolved.headers = request.headers.map { item in
            KeyValueItem(id: item.id, key: interpolate(item.key), value: interpolate(item.value), isEnabled: item.isEnabled)
        }
        resolved.queryParams = request.queryParams.map { item in
            KeyValueItem(id: item.id, key: interpolate(item.key), value: interpolate(item.value), isEnabled: item.isEnabled)
        }
        var resolvedAuth = request.auth
        resolvedAuth.bearerToken = interpolate(request.auth.bearerToken)
        resolvedAuth.basicUsername = interpolate(request.auth.basicUsername)
        resolvedAuth.basicPassword = interpolate(request.auth.basicPassword)
        resolvedAuth.apiKeyName = interpolate(request.auth.apiKeyName)
        resolvedAuth.apiKeyValue = interpolate(request.auth.apiKeyValue)
        resolved.auth = resolvedAuth

        switch resolved.auth.type {
        case .bearer:
            if !resolved.auth.bearerToken.isEmpty {
                if !resolved.headers.contains(where: { $0.key.lowercased() == "authorization" && $0.isEnabled }) {
                    resolved.headers.append(KeyValueItem(key: "Authorization", value: "Bearer \(resolved.auth.bearerToken)", isEnabled: true))
                }
            }
        case .basic:
            if !resolved.auth.basicUsername.isEmpty || !resolved.auth.basicPassword.isEmpty {
                let credentials = "\(resolved.auth.basicUsername):\(resolved.auth.basicPassword)"
                if let credData = credentials.data(using: .utf8) {
                    let base64 = credData.base64EncodedString()
                    if !resolved.headers.contains(where: { $0.key.lowercased() == "authorization" && $0.isEnabled }) {
                        resolved.headers.append(KeyValueItem(key: "Authorization", value: "Basic \(base64)", isEnabled: true))
                    }
                }
            }
        case .apiKey:
            if resolved.auth.apiKeyLocation == .header && !resolved.auth.apiKeyName.isEmpty && !resolved.auth.apiKeyValue.isEmpty {
                if !resolved.headers.contains(where: { $0.key.lowercased() == resolved.auth.apiKeyName.lowercased() && $0.isEnabled }) {
                    resolved.headers.append(KeyValueItem(key: resolved.auth.apiKeyName, value: resolved.auth.apiKeyValue, isEnabled: true))
                }
            }
        case .none:
            break
        }

        return resolved
    }

    public func setExtractedVariable(key: String, value: String) {
        guard !key.isEmpty else { return }
        let targetEnvId: UUID
        if let selected = selectedEnvironmentID, environments.contains(where: { $0.id == selected }) {
            targetEnvId = selected
        } else if let first = environments.first {
            targetEnvId = first.id
            selectedEnvironmentID = first.id
        } else {
            let newEnv = PostEnvironment(name: "Default", variables: [])
            environments.append(newEnv)
            selectedEnvironmentID = newEnv.id
            targetEnvId = newEnv.id
        }

        guard let idx = environments.firstIndex(where: { $0.id == targetEnvId }) else { return }
        if let varIdx = environments[idx].variables.firstIndex(where: { $0.key == key }) {
            environments[idx].variables[varIdx].value = value
        } else {
            environments[idx].variables.append(EnvironmentVariable(key: key, value: value, isSecret: false, isEnabled: true))
        }
        saveToDisk()
    }

    public static func extractJSONValue(from jsonString: String, path: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        var cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("$.") {
            cleanPath.removeFirst(2)
        } else if cleanPath.hasPrefix("$") {
            cleanPath.removeFirst(1)
        }
        cleanPath = cleanPath.replacingOccurrences(of: "[", with: ".")
        cleanPath = cleanPath.replacingOccurrences(of: "]", with: "")
        let segments = cleanPath.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }

        var current: Any = root
        for segment in segments {
            if let dict = current as? [String: Any] {
                if let next = dict[segment] {
                    current = next
                } else {
                    return nil
                }
            } else if let array = current as? [Any], let index = Int(segment), index >= 0, index < array.count {
                current = array[index]
            } else {
                return nil
            }
        }

        if let str = current as? String {
            return str
        } else if let num = current as? NSNumber {
            return num.stringValue
        } else if let dict = current as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                  let str = String(data: data, encoding: .utf8) {
            return str
        } else if let arr = current as? [Any],
                  let data = try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys]),
                  let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: current)
    }

    public func executeSelectedRequest() async {
        guard let request = selectedRequest else { return }
        isExecuting = true
        errorMessage = nil

        let resolved = resolvedRequest(request)

        do {
            let response = try await HTTPClient.shared.execute(request: resolved)
            activeResponse = response

            for rule in request.extractions where rule.isEnabled && !rule.targetVariable.isEmpty && !rule.jsonPath.isEmpty {
                if let extracted = Self.extractJSONValue(from: response.bodyText, path: rule.jsonPath) {
                    setExtractedVariable(key: rule.targetVariable, value: extracted)
                }
            }

            let historyItem = HistoryItem(
                type: .httpRequest,
                title: request.name.isEmpty ? request.url : request.name,
                subtitle: resolved.url,
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

    public func previousResponses(for requestId: UUID) -> [HTTPResponse] {
        history.compactMap { item in
            guard let resp = item.responseData else { return nil }
            if item.requestData?.id == requestId || resp.requestId == requestId {
                return resp
            }
            return nil
        }
    }

    public func convertWebhookToRequest(_ payload: WebhookPayload) {
        let method = HTTPMethod(rawValue: payload.method.uppercased()) ?? .post
        let path = payload.path.hasPrefix("/") ? payload.path : "/\(payload.path)"
        let url = payload.path.hasPrefix("http") ? payload.path : "http://localhost:\(webhookServer.port)\(path)"
        let name = "Webhook \(payload.method.uppercased()) \(payload.path)"
        let bodyType: BodyType = payload.body.isEmpty ? .none : (payload.body.trimmingCharacters(in: .whitespaces).hasPrefix("{") ? .json : .raw)
        let req = HTTPRequest(
            name: name,
            method: method,
            url: url,
            headers: payload.headers,
            bodyType: bodyType,
            bodyText: payload.body,
            collectionId: selectedCollectionID
        )
        requests.append(req)
        selectedRequestID = req.id
        activeTab = .requests
        saveToDisk()
    }

    public func replayWebhook(_ payload: WebhookPayload, to targetURL: String) async {
        let method = HTTPMethod(rawValue: payload.method.uppercased()) ?? .post
        let bodyType: BodyType = payload.body.isEmpty ? .none : (payload.body.trimmingCharacters(in: .whitespaces).hasPrefix("{") ? .json : .raw)
        let req = HTTPRequest(
            name: "Replay: \(payload.method) to \(targetURL)",
            method: method,
            url: targetURL,
            headers: payload.headers,
            bodyType: bodyType,
            bodyText: payload.body,
            collectionId: selectedCollectionID
        )
        do {
            let response = try await HTTPClient.shared.execute(request: req)
            let item = HistoryItem(
                type: .httpRequest,
                title: "Replay: \(payload.method) \(targetURL)",
                subtitle: targetURL,
                method: req.method.rawValue,
                statusCode: response.statusCode,
                durationMs: response.responseTimeMs,
                timestamp: response.timestamp,
                requestData: req,
                responseData: response
            )
            history.insert(item, at: 0)
        } catch {
            let failedResponse = HTTPResponse(
                requestId: req.id,
                statusCode: 0,
                statusText: "Replay Failed",
                bodyText: error.localizedDescription,
                responseTimeMs: 0,
                responseSizeBytes: 0,
                timestamp: Date()
            )
            let item = HistoryItem(
                type: .httpRequest,
                title: "Replay Failed: \(targetURL)",
                subtitle: targetURL,
                method: req.method.rawValue,
                statusCode: 0,
                timestamp: Date(),
                requestData: req,
                responseData: failedResponse
            )
            history.insert(item, at: 0)
        }
    }

    public func importCURL(curlCommand: String) {
        if var parsed = CURLParser.parse(curlCommand: curlCommand) {
            parsed.collectionId = selectedCollectionID
            requests.append(parsed)
            selectedRequestID = parsed.id
            activeResponse = nil
            saveToDisk()
        }
    }

    public func saveToDisk() {
        guard persistenceEnabled else { return }
        do {
            let dir = storageURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let workspace = WorkspaceData(
                requests: requests,
                environments: environments,
                selectedEnvironmentID: selectedEnvironmentID,
                collections: collections,
                selectedCollectionID: selectedCollectionID,
                mcpServers: mcpServers,
                selectedRequestID: selectedRequestID
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workspace)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save workspace to disk: \(error)")
        }
    }

    @discardableResult
    public func loadWorkspaceFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return false
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let workspace = try decoder.decode(WorkspaceData.self, from: data)
            self.requests = workspace.requests
            self.environments = workspace.environments
            self.selectedEnvironmentID = workspace.selectedEnvironmentID
            self.collections = workspace.collections
            self.selectedCollectionID = workspace.selectedCollectionID
            self.mcpServers = workspace.mcpServers
            self.selectedRequestID = workspace.selectedRequestID ?? self.requests.first?.id
            return true
        } catch {
            print("Failed to load workspace from disk: \(error)")
            return false
        }
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let postDir = appSupport.appendingPathComponent("Post", isDirectory: true)
        return postDir.appendingPathComponent("workspace.json")
    }

    public func resetToSampleData() {
        seedSampleData()
        saveToDisk()
    }

    private func seedSampleData() {
        let colAPI = RequestCollection(name: "API Endpoints", iconName: "folder")
        let colAuth = RequestCollection(name: "Auth & Chaining", iconName: "bolt")
        let colWebhooks = RequestCollection(name: "Webhooks & Loopback", iconName: "tray")
        let colHomeLab = RequestCollection(name: "HomeLab & IoT", iconName: "network")
        let colAI = RequestCollection(name: "AI & LLM Gateways", iconName: "star")
        let colDiag = RequestCollection(name: "HTTPBin Diagnostics", iconName: "globe")
        collections = [colAPI, colAuth, colWebhooks, colHomeLab, colAI, colDiag]
        selectedCollectionID = nil

        let envLocal = PostEnvironment(
            name: "Local Dev",
            variables: [
                EnvironmentVariable(key: "base_url", value: "http://localhost:8080", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "webhook_url", value: "http://localhost:9090", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "jwt_token", value: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.local_dev_seed", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "api_key", value: "sk-local-dev-workbench-9000", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "user_id", value: "1", isSecret: false, isEnabled: true)
            ]
        )
        let envProd = PostEnvironment(
            name: "Production (JSONPlaceholder)",
            variables: [
                EnvironmentVariable(key: "base_url", value: "https://jsonplaceholder.typicode.com", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "webhook_url", value: "http://localhost:9090", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "jwt_token", value: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.prod_live", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "api_key", value: "pk-live-prod-key-2026", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "user_id", value: "1", isSecret: false, isEnabled: true)
            ]
        )
        KeychainHelper.shared.setSecret("llat-homeassistant-demo-token", forKey: "ha_token")
        let envHomeLab = PostEnvironment(
            name: "HomeLab & Home Assistant",
            variables: [
                EnvironmentVariable(key: "ha_url", value: "http://homeassistant.local:8123", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "router_url", value: "http://192.168.1.1:8000", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "ha_token", value: "llat-homeassistant-demo-token", isSecret: true, isEnabled: true),
                EnvironmentVariable(key: "cloudflare_token", value: "op://HomeLab/Cloudflare/api_token", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "entity_id", value: "light.office_desk", isSecret: false, isEnabled: true)
            ]
        )
        let envSandbox = PostEnvironment(
            name: "HTTPBin Sandbox",
            variables: [
                EnvironmentVariable(key: "httpbin_url", value: "https://httpbin.org", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "basic_user", value: "admin", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "basic_pass", value: "hunter2", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "api_key", value: "sk-httpbin-sandbox-42", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "jwt_token", value: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sandbox", isSecret: false, isEnabled: true)
            ]
        )
        environments = [envLocal, envProd, envHomeLab, envSandbox]
        selectedEnvironmentID = envLocal.id

        // --- Collection 1: API Endpoints ---
        let reqUser = HTTPRequest(
            name: "Get User Profile",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/users/{{user_id}}",
            headers: [
                KeyValueItem(key: "Accept", value: "application/json", isEnabled: true),
                KeyValueItem(key: "User-Agent", value: "Post-Mac/1.0", isEnabled: true)
            ],
            collectionId: colAPI.id
        )
        let reqPosts = HTTPRequest(
            name: "List User Posts (JSONPath & Diff)",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/posts",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            queryParams: [
                KeyValueItem(key: "userId", value: "{{user_id}}", isEnabled: true),
                KeyValueItem(key: "_limit", value: "5", isEnabled: true)
            ],
            collectionId: colAPI.id
        )
        let reqCreatePost = HTTPRequest(
            name: "Create Blog Post",
            method: .post,
            url: "https://jsonplaceholder.typicode.com/posts",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"title\": \"release.v2.shipped\",\n  \"body\": \"Native macOS HTTP, Webhook, and MCP workbench\",\n  \"userId\": 1\n}",
            collectionId: colAPI.id,
            extractions: [
                ResponseExtractionRule(jsonPath: "$.id", targetVariable: "last_post_id", isEnabled: true)
            ]
        )
        let reqPatchPost = HTTPRequest(
            name: "Patch Post Title",
            method: .patch,
            url: "https://jsonplaceholder.typicode.com/posts/1",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"title\": \"patched.via.post.workbench\"\n}",
            collectionId: colAPI.id
        )
        let reqTodo = HTTPRequest(
            name: "Get Sample Todo",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/todos/1",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            collectionId: colAPI.id
        )

        // --- Collection 2: Auth & Chaining ---
        let reqAuthLogin = HTTPRequest(
            name: "1. Auth Login (Extract JWT & User ID)",
            method: .post,
            url: "https://httpbin.org/anything/auth/login",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"access_token\": \"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.live_chained_token_2026\",\n  \"token_type\": \"Bearer\",\n  \"expires_in\": 3600,\n  \"user\": {\n    \"id\": 7,\n    \"email\": \"ops@homelab.local\",\n    \"role\": \"platform_admin\"\n  }\n}",
            collectionId: colAuth.id,
            extractions: [
                ResponseExtractionRule(jsonPath: "$.json.access_token", targetVariable: "jwt_token", isEnabled: true),
                ResponseExtractionRule(jsonPath: "$.json.user.id", targetVariable: "user_id", isEnabled: true)
            ]
        )
        let reqBearerVerify = HTTPRequest(
            name: "2. Verify Chained Bearer Token",
            method: .get,
            url: "https://httpbin.org/bearer",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            collectionId: colAuth.id,
            auth: AuthConfig(type: .bearer, bearerToken: "{{jwt_token}}")
        )
        let reqBasicAuth = HTTPRequest(
            name: "3. Basic Auth Challenge",
            method: .get,
            url: "https://httpbin.org/basic-auth/admin/hunter2",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            collectionId: colAuth.id,
            auth: AuthConfig(type: .basic, basicUsername: "admin", basicPassword: "hunter2")
        )
        let reqApiKeyAuth = HTTPRequest(
            name: "4. API Key Gateway Inspection",
            method: .get,
            url: "https://httpbin.org/get",
            queryParams: [
                KeyValueItem(key: "service", value: "billing-v2", isEnabled: true),
                KeyValueItem(key: "region", value: "us-east", isEnabled: true)
            ],
            collectionId: colAuth.id,
            auth: AuthConfig(
                type: .apiKey,
                apiKeyName: "X-Workspace-Key",
                apiKeyValue: "{{api_key}}",
                apiKeyLocation: .header
            )
        )

        // --- Collection 3: Webhooks & Loopback ---
        let reqWebhookStripe = HTTPRequest(
            name: "Stripe Payment Webhook (200 OK)",
            method: .post,
            url: "http://localhost:9090/webhook",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true),
                KeyValueItem(key: "Stripe-Signature", value: "t=1728990120,v1=5a8c91e0f2d4b6a1...", isEnabled: true)
            ],
            bodyType: .json,
            bodyText: "{\n  \"id\": \"evt_3Q9xYz2eZvKYlo2C\",\n  \"type\": \"payment_intent.succeeded\",\n  \"data\": {\n    \"object\": {\n      \"id\": \"pi_3Q9xYz\",\n      \"amount\": 4900,\n      \"currency\": \"usd\",\n      \"customer\": \"cus_R1x90a\",\n      \"status\": \"succeeded\"\n    }\n  }\n}",
            collectionId: colWebhooks.id
        )
        let reqWebhookGitHub = HTTPRequest(
            name: "GitHub Push Webhook (202 Queued)",
            method: .post,
            url: "http://localhost:9090/webhook/github",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true),
                KeyValueItem(key: "X-GitHub-Event", value: "push", isEnabled: true),
                KeyValueItem(key: "X-Hub-Signature-256", value: "sha256=9f8e7d6c5b4a3f2e1d...", isEnabled: true)
            ],
            bodyType: .json,
            bodyText: "{\n  \"ref\": \"refs/heads/main\",\n  \"repository\": {\n    \"full_name\": \"msjurset/post-mac\",\n    \"private\": false\n  },\n  \"pusher\": {\n    \"name\": \"msjurset\"\n  },\n  \"head_commit\": {\n    \"id\": \"8c4b2f10a\",\n    \"message\": \"Add MCP stdio transport and webhook replay\"\n  }\n}",
            collectionId: colWebhooks.id
        )
        let reqWebhookRateLimit = HTTPRequest(
            name: "Simulate 429 Rate Limit Rule",
            method: .post,
            url: "http://localhost:9090/webhook/rate-limit",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"event\": \"sync.burst\",\n  \"batch_size\": 500,\n  \"tenant\": \"acme-corp\"\n}",
            collectionId: colWebhooks.id
        )
        let reqWebhookChaos = HTTPRequest(
            name: "Simulate 503 Slow Upstream Chaos",
            method: .post,
            url: "http://localhost:9090/webhook/chaos",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"event\": \"invoice.reconcile\",\n  \"attempt\": 3\n}",
            collectionId: colWebhooks.id
        )

        // --- Collection 4: HomeLab & IoT ---
        let reqHAState = HTTPRequest(
            name: "Home Assistant - Inspect Entity State",
            method: .get,
            url: "{{ha_url}}/api/states/{{entity_id}}",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            collectionId: colHomeLab.id,
            auth: AuthConfig(type: .bearer, bearerToken: "{{ha_token}}")
        )
        let reqHAToggle = HTTPRequest(
            name: "Home Assistant - Toggle Office Light",
            method: .post,
            url: "{{ha_url}}/api/services/light/toggle",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"entity_id\": \"{{entity_id}}\",\n  \"transition\": 1\n}",
            collectionId: colHomeLab.id,
            auth: AuthConfig(type: .bearer, bearerToken: "{{ha_token}}")
        )

        // --- Collection 5: AI & LLM Gateways ---
        let reqOllama = HTTPRequest(
            name: "Ollama Local - Generate Completion",
            method: .post,
            url: "http://localhost:11434/api/generate",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\n  \"model\": \"llama3.2\",\n  \"prompt\": \"Summarize HTTP/3 QUIC transport benefits in 3 concise bullet points.\",\n  \"stream\": false\n}",
            collectionId: colAI.id,
            extractions: [
                ResponseExtractionRule(jsonPath: "$.response", targetVariable: "last_llm_reply", isEnabled: true)
            ]
        )
        let reqGitHubRepo = HTTPRequest(
            name: "GitHub API - SwiftNIO Repo Telemetry",
            method: .get,
            url: "https://api.github.com/repos/apple/swift-nio",
            headers: [
                KeyValueItem(key: "Accept", value: "application/vnd.github+json", isEnabled: true),
                KeyValueItem(key: "User-Agent", value: "Post-Mac/1.0", isEnabled: true)
            ],
            collectionId: colAI.id
        )

        // --- Collection 6: HTTPBin Diagnostics ---
        let reqFormOAuth = HTTPRequest(
            name: "OAuth2 Form-UrlEncoded Token Request",
            method: .post,
            url: "https://httpbin.org/post",
            headers: [KeyValueItem(key: "Accept", value: "application/json", isEnabled: true)],
            bodyType: .formData,
            bodyText: "grant_type=client_credentials&client_id=post-workbench&scope=read%3Aall%20write%3Awebhooks",
            collectionId: colDiag.id
        )
        let reqDiagHeaders = HTTPRequest(
            name: "Echo Client Headers & Correlation ID",
            method: .get,
            url: "https://httpbin.org/anything/diagnostics",
            headers: [
                KeyValueItem(key: "X-Correlation-ID", value: "req-99481-post", isEnabled: true),
                KeyValueItem(key: "X-Client-Platform", value: "macOS-ARM64", isEnabled: true)
            ],
            queryParams: [
                KeyValueItem(key: "trace", value: "true", isEnabled: true),
                KeyValueItem(key: "env", value: "macos-workbench", isEnabled: true)
            ],
            collectionId: colDiag.id
        )

        requests = [
            reqUser, reqPosts, reqCreatePost, reqPatchPost, reqTodo,
            reqAuthLogin, reqBearerVerify, reqBasicAuth, reqApiKeyAuth,
            reqWebhookStripe, reqWebhookGitHub, reqWebhookRateLimit, reqWebhookChaos,
            reqHAState, reqHAToggle,
            reqOllama, reqGitHubRepo,
            reqFormOAuth, reqDiagHeaders
        ]
        selectedRequestID = reqUser.id

        seedSampleRuntimeHistoryAndWebhooks(primaryRequest: reqUser)

        // --- Pre-Seed 4 Rich MCP Server Profiles (SSE + Stdio with JSON Schemas, Resources & Prompts) ---
        let routerTools = [
            MCPToolInfo(
                name: "get_system_health",
                description: "Retrieve CPU load, RAM usage, thermal sensors, and uptime metrics for router node.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "interface": { "type": "string", "description": "Network interface (e.g. eth0, br-lan)" },
                    "verbose": { "type": "boolean", "description": "Include per-core CPU and thermal details" }
                  },
                  "required": ["interface"]
                }
                """
            ),
            MCPToolInfo(
                name: "list_dhcp_leases",
                description: "List all active client DHCPv4/v6 leases on the local subnet.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "subnet": { "type": "string", "description": "Filter by subnet CIDR (e.g. 192.168.1.0/24)" },
                    "active_only": { "type": "boolean", "description": "Only return currently reachable hosts" }
                  }
                }
                """
            ),
            MCPToolInfo(
                name: "ping_diagnostic",
                description: "Run an ICMP latency and packet-loss probe from the router to a target host.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "host": { "type": "string", "description": "Target hostname or IPv4/IPv6 address" },
                    "count": { "type": "integer", "description": "Number of ICMP echo packets (1-20)" }
                  },
                  "required": ["host"]
                }
                """
            )
        ]
        let routerResources = [
            MCPResourceInfo(
                uri: "mcp://router/config/network",
                name: "UCI Network Configuration",
                description: "Current VLAN, bridge, and WAN interface definitions",
                mimeType: "application/json"
            ),
            MCPResourceInfo(
                uri: "mcp://router/logs/syslog",
                name: "System Kernel & Daemon Ringbuffer",
                description: "Last 200 lines of router syslog output",
                mimeType: "text/plain"
            )
        ]
        let routerPrompts = [
            MCPPromptInfo(
                name: "diagnose_packet_loss",
                description: "Guided multi-step WAN latency and bufferbloat triage workflow"
            ),
            MCPPromptInfo(
                name: "audit_firewall_zones",
                description: "Inspect port forwards and UPnP leases for unintended exposure"
            )
        ]

        let haTools = [
            MCPToolInfo(
                name: "ha_get_state",
                description: "Fetch the current state and attributes of a Home Assistant entity.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "entity_id": { "type": "string", "description": "Entity ID (e.g. light.office_desk, climate.thermostat)" }
                  },
                  "required": ["entity_id"]
                }
                """
            ),
            MCPToolInfo(
                name: "ha_call_service",
                description: "Call any Home Assistant domain service (light.turn_on, lock.lock, script.run).",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "domain": { "type": "string", "description": "Service domain (e.g. light, switch, climate)" },
                    "service": { "type": "string", "description": "Service action name (e.g. turn_on, toggle)" },
                    "entity_id": { "type": "string", "description": "Target entity ID" }
                  },
                  "required": ["domain", "service", "entity_id"]
                }
                """
            ),
            MCPToolInfo(
                name: "ha_eval_template",
                description: "Evaluate a Jinja2 template string against live Home Assistant state.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "template": { "type": "string", "description": "Jinja2 expression e.g. {{ states('sensor.power_load') }}" }
                  },
                  "required": ["template"]
                }
                """
            )
        ]
        let haResources = [
            MCPResourceInfo(
                uri: "ha://entities/overview",
                name: "Entity Registry Summary",
                description: "All registered areas, floors, and active entities by domain",
                mimeType: "application/json"
            ),
            MCPResourceInfo(
                uri: "ha://automations/recent_traces",
                name: "Recent Automation Execution Traces",
                description: "Trigger paths and condition evaluations for the last 25 runs",
                mimeType: "application/json"
            )
        ]
        let haPrompts = [
            MCPPromptInfo(
                name: "energy_consumption_audit",
                description: "Analyze high-draw circuits and recommend off-peak automation schedules"
            )
        ]

        let fsTools = [
            MCPToolInfo(
                name: "read_file",
                description: "Read the UTF-8 contents of a file inside the allowed workspace directory.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "path": { "type": "string", "description": "Absolute or workspace-relative file path" }
                  },
                  "required": ["path"]
                }
                """
            ),
            MCPToolInfo(
                name: "search_files",
                description: "Recursively search for files matching a glob pattern or substring.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "path": { "type": "string", "description": "Root directory to search" },
                    "pattern": { "type": "string", "description": "Search pattern (e.g. *.swift, Package.swift)" }
                  },
                  "required": ["path", "pattern"]
                }
                """
            )
        ]
        let fsResources = [
            MCPResourceInfo(
                uri: "file:///Users/msjurseth/workspace/swift/post-mac/README.md",
                name: "Post Workspace README.md",
                description: "Project architecture and quick-start documentation",
                mimeType: "text/markdown"
            )
        ]
        let fsPrompts = [
            MCPPromptInfo(
                name: "architecture_review",
                description: "Summarize Swift package targets, models, and concurrency boundaries"
            )
        ]

        let sqliteTools = [
            MCPToolInfo(
                name: "read_query",
                description: "Execute a read-only SELECT query against the SQLite database.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "query": { "type": "string", "description": "SQL SELECT statement" },
                    "limit": { "type": "integer", "description": "Maximum rows to return" }
                  },
                  "required": ["query"]
                }
                """
            ),
            MCPToolInfo(
                name: "describe_table",
                description: "Inspect columns, types, and indexes for a specific SQLite table.",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "table_name": { "type": "string", "description": "Name of the table to inspect" }
                  },
                  "required": ["table_name"]
                }
                """
            )
        ]

        let server1 = MCPServer(
            name: "Router & Network MCP",
            endpoint: "http://localhost:8000/sse",
            type: .sse,
            tools: routerTools,
            resources: routerResources,
            prompts: routerPrompts,
            isConnected: true
        )
        let server2 = MCPServer(
            name: "Home Assistant MCP",
            endpoint: "http://homeassistant.local:8123/mcp_server/sse",
            type: .sse,
            tools: haTools,
            resources: haResources,
            prompts: haPrompts,
            isConnected: true
        )
        let server3 = MCPServer(
            name: "Workspace Filesystem (Stdio)",
            endpoint: "npx -y @modelcontextprotocol/server-filesystem /Users/msjurseth/workspace",
            type: .stdio,
            tools: fsTools,
            resources: fsResources,
            prompts: fsPrompts,
            isConnected: false
        )
        let server4 = MCPServer(
            name: "SQLite Inspector (Stdio)",
            endpoint: "sqlite3 -json ~/Library/Application\\ Support/Post/workspace.db",
            type: .stdio,
            tools: sqliteTools,
            resources: [
                MCPResourceInfo(
                    uri: "sqlite://main/schema",
                    name: "Database DDL Schema",
                    description: "CREATE TABLE statements for all user tables",
                    mimeType: "application/sql"
                )
            ],
            prompts: [
                MCPPromptInfo(name: "index_optimization_check", description: "Identify queries missing covering indexes")
            ],
            isConnected: false
        )

        mcpServers = [server1, server2, server3, server4]
        selectedMCPServerID = server1.id
    }

    private func seedSampleRuntimeHistoryAndWebhooks(primaryRequest: HTTPRequest?) {
        let sampleWebhook1 = WebhookPayload(
            timestamp: Date().addingTimeInterval(-420),
            method: "POST",
            path: "/webhook/stripe",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json"),
                KeyValueItem(key: "Stripe-Signature", value: "t=1728990120,v1=5a8c91e0f2d4b6a1"),
                KeyValueItem(key: "User-Agent", value: "Stripe/1.0 (+https://stripe.com/docs/webhooks)")
            ],
            body: "{\n  \"id\": \"evt_3Q9xYz2eZvKYlo2C\",\n  \"type\": \"payment_intent.succeeded\",\n  \"data\": {\n    \"object\": {\n      \"id\": \"pi_3Q9xYz\",\n      \"amount\": 4900,\n      \"currency\": \"usd\",\n      \"customer\": \"cus_R1x90a\",\n      \"status\": \"succeeded\"\n    }\n  }\n}",
            clientIP: "127.0.0.1:54102",
            responseStatusCode: 200
        )
        let sampleWebhook2 = WebhookPayload(
            timestamp: Date().addingTimeInterval(-180),
            method: "POST",
            path: "/webhook/github",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json"),
                KeyValueItem(key: "X-GitHub-Event", value: "push"),
                KeyValueItem(key: "X-GitHub-Delivery", value: "72d3162e-cc78-11e3-81ab-4c9367dc0958")
            ],
            body: "{\n  \"ref\": \"refs/heads/main\",\n  \"repository\": {\n    \"full_name\": \"msjurset/post-mac\"\n  },\n  \"pusher\": {\n    \"name\": \"msjurset\"\n  },\n  \"head_commit\": {\n    \"id\": \"8c4b2f10a\",\n    \"message\": \"Add MCP stdio transport and webhook replay\"\n  }\n}",
            clientIP: "192.168.1.44:61204",
            responseStatusCode: 202
        )
        let sampleWebhook3 = WebhookPayload(
            timestamp: Date().addingTimeInterval(-45),
            method: "POST",
            path: "/webhook/rate-limit",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json"),
                KeyValueItem(key: "X-Alertmanager-Version", value: "0.27.0")
            ],
            body: "{\n  \"receiver\": \"homelab-pager\",\n  \"status\": \"firing\",\n  \"alerts\": [\n    {\n      \"status\": \"firing\",\n      \"labels\": {\n        \"alertname\": \"HighMemoryPressure\",\n        \"instance\": \"proxmox-node-01:9100\",\n        \"severity\": \"warning\"\n      }\n    }\n  ]\n}",
            clientIP: "192.168.1.10:39812",
            responseStatusCode: 429
        )
        webhookServer.payloads = [sampleWebhook3, sampleWebhook2, sampleWebhook1]

        let targetReq = primaryRequest ?? HTTPRequest(
            name: "Get User Profile",
            method: .get,
            url: "https://jsonplaceholder.typicode.com/users/1"
        )

        let baselineUserBody = """
        {
          "id": 1,
          "name": "Leanne Graham",
          "username": "Bret",
          "email": "Sincere@april.biz",
          "role": "member",
          "address": {
            "street": "Kulas Light",
            "city": "Gwenborough",
            "zipcode": "92998-3874"
          },
          "company": {
            "name": "Romaguera-Crona"
          }
        }
        """
        let latestUserBody = """
        {
          "id": 1,
          "name": "Leanne Graham",
          "username": "Bret",
          "email": "leanne.graham@april.biz",
          "role": "platform_admin",
          "address": {
            "street": "Kulas Light",
            "city": "Gwenborough",
            "zipcode": "92998-3874"
          },
          "company": {
            "name": "Romaguera-Crona",
            "tier": "enterprise"
          }
        }
        """
        let respUserOld = HTTPResponse(
            requestId: targetReq.id,
            statusCode: 200,
            statusText: "OK",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json; charset=utf-8"),
                KeyValueItem(key: "Cache-Control", value: "max-age=43200")
            ],
            bodyText: baselineUserBody,
            responseTimeMs: 118.4,
            responseSizeBytes: Int64(baselineUserBody.utf8.count),
            timestamp: Date().addingTimeInterval(-600)
        )
        let respUserLatest = HTTPResponse(
            requestId: targetReq.id,
            statusCode: 200,
            statusText: "OK",
            headers: [
                KeyValueItem(key: "Content-Type", value: "application/json; charset=utf-8"),
                KeyValueItem(key: "X-Cache", value: "HIT")
            ],
            bodyText: latestUserBody,
            responseTimeMs: 42.7,
            responseSizeBytes: Int64(latestUserBody.utf8.count),
            timestamp: Date().addingTimeInterval(-90)
        )
        activeResponse = respUserLatest

        history = [
            HistoryItem(
                type: .httpRequest,
                title: targetReq.name,
                subtitle: "https://jsonplaceholder.typicode.com/users/1",
                method: "GET",
                statusCode: 200,
                durationMs: 42.7,
                timestamp: Date().addingTimeInterval(-90),
                requestData: targetReq,
                responseData: respUserLatest
            ),
            HistoryItem(
                type: .webhook,
                title: "POST /webhook/rate-limit",
                subtitle: "192.168.1.10:39812",
                method: "POST",
                statusCode: 429,
                timestamp: sampleWebhook3.timestamp,
                webhookData: sampleWebhook3
            ),
            HistoryItem(
                type: .webhook,
                title: "POST /webhook/github",
                subtitle: "192.168.1.44:61204",
                method: "POST",
                statusCode: 202,
                timestamp: sampleWebhook2.timestamp,
                webhookData: sampleWebhook2
            ),
            HistoryItem(
                type: .httpRequest,
                title: targetReq.name,
                subtitle: "https://jsonplaceholder.typicode.com/users/1 (Baseline)",
                method: "GET",
                statusCode: 200,
                durationMs: 118.4,
                timestamp: Date().addingTimeInterval(-600),
                requestData: targetReq,
                responseData: respUserOld
            )
        ]
    }
}

private struct WorkspaceData: Codable {
    var requests: [HTTPRequest]
    var environments: [PostEnvironment]
    var selectedEnvironmentID: UUID?
    var collections: [RequestCollection]
    var selectedCollectionID: UUID?
    var mcpServers: [MCPServer]
    var selectedRequestID: UUID?

    enum CodingKeys: CodingKey {
        case requests, environments, selectedEnvironmentID, collections, selectedCollectionID, mcpServers, selectedRequestID
    }

    init(
        requests: [HTTPRequest],
        environments: [PostEnvironment],
        selectedEnvironmentID: UUID?,
        collections: [RequestCollection],
        selectedCollectionID: UUID?,
        mcpServers: [MCPServer],
        selectedRequestID: UUID?
    ) {
        self.requests = requests
        self.environments = environments
        self.selectedEnvironmentID = selectedEnvironmentID
        self.collections = collections
        self.selectedCollectionID = selectedCollectionID
        self.mcpServers = mcpServers
        self.selectedRequestID = selectedRequestID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requests = try container.decodeIfPresent([HTTPRequest].self, forKey: .requests) ?? []
        self.environments = try container.decodeIfPresent([PostEnvironment].self, forKey: .environments) ?? []
        self.selectedEnvironmentID = try container.decodeIfPresent(UUID.self, forKey: .selectedEnvironmentID)
        self.collections = try container.decodeIfPresent([RequestCollection].self, forKey: .collections) ?? []
        self.selectedCollectionID = try container.decodeIfPresent(UUID.self, forKey: .selectedCollectionID)
        self.mcpServers = try container.decodeIfPresent([MCPServer].self, forKey: .mcpServers) ?? []
        self.selectedRequestID = try container.decodeIfPresent(UUID.self, forKey: .selectedRequestID)
    }
}

private struct SearchFilter {
    var methods: [String] = []
    var statuses: [String] = []
    var types: [String] = []
    var hosts: [String] = []
    var collections: [String] = []
    var freeTexts: [String] = []

    init(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tokens = trimmed.split(separator: " ").map(String.init)
        for token in tokens {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let val = parts[1].lowercased()
                switch key {
                case "method": methods.append(val)
                case "status": statuses.append(val)
                case "type": types.append(val)
                case "host": hosts.append(val)
                case "collection": collections.append(val)
                default: freeTexts.append(token.lowercased())
                }
            } else {
                freeTexts.append(token.lowercased())
            }
        }
    }

    var isEmpty: Bool {
        methods.isEmpty && statuses.isEmpty && types.isEmpty && hosts.isEmpty && collections.isEmpty && freeTexts.isEmpty
    }
}
