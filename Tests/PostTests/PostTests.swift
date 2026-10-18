import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Post

@Suite("Post App Unit Tests")
struct PostTests {

    @Test("HTTPRequest URL Construction")
    func testHTTPRequestURL() {
        let req = HTTPRequest(
            name: "Test Request",
            method: .get,
            url: "https://api.example.com/search",
            queryParams: [
                KeyValueItem(key: "q", value: "swift", isEnabled: true),
                KeyValueItem(key: "limit", value: "10", isEnabled: true),
                KeyValueItem(key: "disabled", value: "val", isEnabled: false)
            ]
        )

        let fullURL = req.fullURL
        #expect(fullURL != nil)
        let absoluteString = fullURL?.absoluteString ?? ""
        #expect(absoluteString.contains("q=swift"))
        #expect(absoluteString.contains("limit=10"))
        #expect(!absoluteString.contains("disabled"))
    }

    @Test("cURL Exporter")
    func testExportToCURL() {
        let req = HTTPRequest(
            name: "Test Post",
            method: .post,
            url: "https://httpbin.org/post",
            headers: [KeyValueItem(key: "Content-Type", value: "application/json", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\"hello\":\"world\"}"
        )

        let curlString = HTTPClient.shared.exportToCURL(request: req)
        #expect(curlString.contains("curl -X POST"))
        #expect(curlString.contains("-H 'Content-Type: application/json'"))
        #expect(curlString.contains("-d '{\"hello\":\"world\"}'"))
        #expect(curlString.contains("'https://httpbin.org/post'"))
    }

    @Test("cURL Parser")
    func testCURLParser() {
        let rawCURL = "curl -X POST https://api.test.com/v1/event -H 'Content-Type: application/json' -d '{\"event\":\"click\"}'"
        let parsed = CURLParser.parse(curlCommand: rawCURL)

        #expect(parsed != nil)
        #expect(parsed?.method == .post)
        #expect(parsed?.url == "https://api.test.com/v1/event")
        #expect(parsed?.headers.contains(where: { $0.key == "Content-Type" && $0.value == "application/json" }) == true)
        #expect(parsed?.bodyText == "{\"event\":\"click\"}")
    }

    @MainActor
    @Test("PostStore Search Filtering")
    func testPostStoreFiltering() {
        let store = PostStore()
        store.history = [
            HistoryItem(type: .httpRequest, title: "Get Users", subtitle: "/api/users", method: "GET", statusCode: 200),
            HistoryItem(type: .httpRequest, title: "Create User", subtitle: "/api/users", method: "POST", statusCode: 201),
            HistoryItem(type: .httpRequest, title: "Error Endpoint", subtitle: "/api/fail", method: "POST", statusCode: 500)
        ]

        store.searchQuery = "method:POST status:500"
        let filtered = store.filteredHistory
        #expect(filtered.count == 1)
        #expect(filtered.first?.statusCode == 500)
    }

    @MainActor
    @Test("Generate Documentation Screenshots")
    func testGenerateDocsScreenshots() {
        let fileManager = FileManager.default
        let docsAssetsDir = "docs/assets"
        try? fileManager.createDirectory(atPath: docsAssetsDir, withIntermediateDirectories: true)

        // 1. HTTP Workbench Overview (Params + Variable Interpolation + Code Export + JSONPath Filter)
        let store1 = PostStore()
        store1.activeTab = .requests
        if let postsReq = store1.requests.first(where: { $0.name.contains("List User Posts") }) {
            store1.selectedRequestID = postsReq.id
        }
        let workbenchCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Stash-Model Token Filter (⌘K)",
                subtitle: "Filter by method:, status:, type:, host:, collection:",
                targetRect: CGRect(x: 8, y: 8, width: 264, height: 32),
                badgeCenter: CGPoint(x: 185, y: 76),
                arrowStart: CGPoint(x: 140, y: 55),
                arrowEnd: CGPoint(x: 140, y: 40),
                color: .cyan
            ),
            DocCallout(
                number: 2,
                title: "Environment & Code Export",
                subtitle: "Switch environments or copy cURL / Go / Swift / Python",
                targetRect: CGRect(x: 718, y: 10, width: 274, height: 32),
                badgeCenter: CGPoint(x: 525, y: 26),
                arrowStart: CGPoint(x: 702, y: 26),
                arrowEnd: CGPoint(x: 718, y: 26),
                color: .orange
            ),
            DocCallout(
                number: 3,
                title: "Dynamic {{variable}} Interpolation",
                subtitle: "Resolves {{user_id}}, Keychain, or op:// secrets on Send",
                targetRect: CGRect(x: 290, y: 132, width: 695, height: 34),
                badgeCenter: CGPoint(x: 765, y: 222),
                arrowStart: CGPoint(x: 700, y: 201),
                arrowEnd: CGPoint(x: 685, y: 166),
                color: .green
            ),
            DocCallout(
                number: 4,
                title: "Live JSONPath Slicing & Diff",
                subtitle: "Filter payload with $.company or diff against prior runs",
                targetRect: CGRect(x: 290, y: 330, width: 700, height: 158),
                badgeCenter: CGPoint(x: 775, y: 532),
                arrowStart: CGPoint(x: 775, y: 511),
                arrowEnd: CGPoint(x: 775, y: 488),
                color: .purple
            )
        ]
        renderView(
            MainContentView(store: store1, initialEditorTab: .params, initialResponseTab: .body, initialJSONPath: "$.company"),
            callouts: workbenchCallouts,
            to: "\(docsAssetsDir)/http_workbench.png"
        )
        renderView(
            MainContentView(store: store1, initialEditorTab: .params, initialResponseTab: .body),
            callouts: workbenchCallouts,
            to: "\(docsAssetsDir)/http_workbench_params.png"
        )

        // 2. Environments, Keychain & 1Password (op://) Manager
        let storeEnv = PostStore()
        if let idx = storeEnv.environments.firstIndex(where: { $0.name.contains("HomeLab") }) {
            storeEnv.environments[idx].variables = Array(storeEnv.environments[idx].variables.prefix(4))
            storeEnv.selectedEnvironmentID = storeEnv.environments[idx].id
        }
        let envCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Switchable Environment Profiles",
                subtitle: "Isolated variables for Local, Prod & HomeLab",
                targetRect: CGRect(x: 8, y: 74, width: 204, height: 215),
                badgeCenter: CGPoint(x: 155, y: 382),
                arrowStart: CGPoint(x: 110, y: 361),
                arrowEnd: CGPoint(x: 110, y: 289),
                color: .cyan
            ),
            DocCallout(
                number: 2,
                title: "macOS Keychain Secret (🔒)",
                subtitle: "Encrypted in Keychain, never stored in JSON",
                targetRect: CGRect(x: 240, y: 270, width: 460, height: 36),
                badgeCenter: CGPoint(x: 565, y: 375),
                arrowStart: CGPoint(x: 666, y: 354),
                arrowEnd: CGPoint(x: 666, y: 306),
                color: .yellow
            ),
            DocCallout(
                number: 3,
                title: "1Password CLI (op://) Secret URI",
                subtitle: "Resolved on-demand via Touch ID & `op read`",
                targetRect: CGRect(x: 240, y: 314, width: 412, height: 36),
                badgeCenter: CGPoint(x: 410, y: 435),
                arrowStart: CGPoint(x: 410, y: 414),
                arrowEnd: CGPoint(x: 410, y: 350),
                color: .blue
            ),
            DocCallout(
                number: 4,
                title: "1Password Session Cache Control",
                subtitle: "Evict cached op:// secrets with one click",
                targetRect: CGRect(x: 464, y: 130, width: 126, height: 32),
                badgeCenter: CGPoint(x: 460, y: 65),
                arrowStart: CGPoint(x: 527, y: 86),
                arrowEnd: CGPoint(x: 527, y: 130),
                color: .orange
            )
        ]
        renderView(
            EnvironmentManagerSheet(store: storeEnv),
            size: CGSize(width: 720, height: 500),
            callouts: envCallouts,
            to: "\(docsAssetsDir)/environments_keychain_1p.png"
        )

        // 3. Zero-Copy Auth Chaining (Chaining Tab)
        let storeChain = PostStore()
        storeChain.activeTab = .requests
        if let loginReq = storeChain.requests.first(where: { $0.name.contains("1. Auth Login") }) {
            storeChain.selectedRequestID = loginReq.id
            let loginRespBody = """
            {
              "json": {
                "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.live_chained_token_2026",
                "token_type": "Bearer",
                "expires_in": 3600,
                "user": {
                  "id": 7,
                  "email": "ops@homelab.local",
                  "role": "platform_admin"
                }
              },
              "url": "https://httpbin.org/anything/auth/login"
            }
            """
            storeChain.activeResponse = HTTPResponse(
                requestId: loginReq.id,
                statusCode: 200,
                statusText: "OK",
                headers: [KeyValueItem(key: "Content-Type", value: "application/json")],
                bodyText: loginRespBody,
                responseTimeMs: 84.2,
                responseSizeBytes: Int64(loginRespBody.utf8.count)
            )
        }
        let chainingCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Response Chaining Tab",
                subtitle: "Extract fields from JSON responses into variables",
                targetRect: CGRect(x: 750, y: 86, width: 80, height: 28),
                badgeCenter: CGPoint(x: 800, y: 52),
                arrowStart: CGPoint(x: 790, y: 73),
                arrowEnd: CGPoint(x: 790, y: 86),
                color: .orange
            ),
            DocCallout(
                number: 2,
                title: "JSONPath Extraction Rules",
                subtitle: "Evaluates $.json.access_token and $.json.user.id",
                targetRect: CGRect(x: 292, y: 132, width: 335, height: 70),
                badgeCenter: CGPoint(x: 455, y: 242),
                arrowStart: CGPoint(x: 455, y: 221),
                arrowEnd: CGPoint(x: 455, y: 202),
                color: .cyan
            ),
            DocCallout(
                number: 3,
                title: "Target Environment Variables",
                subtitle: "Updates {{jwt_token}} and {{user_id}} automatically",
                targetRect: CGRect(x: 645, y: 132, width: 315, height: 70),
                badgeCenter: CGPoint(x: 815, y: 242),
                arrowStart: CGPoint(x: 815, y: 221),
                arrowEnd: CGPoint(x: 815, y: 202),
                color: .green
            )
        ]
        renderView(
            MainContentView(store: storeChain, initialEditorTab: .chaining, initialResponseTab: .body),
            callouts: chainingCallouts,
            to: "\(docsAssetsDir)/auth_chaining.png"
        )

        // 4. Dedicated Auth Presets (Bearer Token with {{jwt_token}})
        let storeAuth = PostStore()
        storeAuth.activeTab = .requests
        if let verifyReq = storeAuth.requests.first(where: { $0.name.contains("2. Verify Chained Bearer") }) {
            storeAuth.selectedRequestID = verifyReq.id
            let bearerRespBody = """
            {
              "authenticated": true,
              "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.live_chained_token_2026"
            }
            """
            storeAuth.activeResponse = HTTPResponse(
                requestId: verifyReq.id,
                statusCode: 200,
                statusText: "OK",
                headers: [KeyValueItem(key: "Content-Type", value: "application/json")],
                bodyText: bearerRespBody,
                responseTimeMs: 61.5,
                responseSizeBytes: Int64(bearerRespBody.utf8.count)
            )
        }
        let authCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Dedicated Auth Tab",
                subtitle: "Bearer Token, Basic Auth & API Key presets",
                targetRect: CGRect(x: 534, y: 86, width: 68, height: 28),
                badgeCenter: CGPoint(x: 800, y: 100),
                arrowStart: CGPoint(x: 640, y: 100),
                arrowEnd: CGPoint(x: 602, y: 100),
                color: .cyan
            ),
            DocCallout(
                number: 2,
                title: "Chained {{jwt_token}} Injection",
                subtitle: "Injects Authorization: Bearer <token> on Send",
                targetRect: CGRect(x: 292, y: 132, width: 685, height: 96),
                badgeCenter: CGPoint(x: 780, y: 262),
                arrowStart: CGPoint(x: 780, y: 241),
                arrowEnd: CGPoint(x: 780, y: 228),
                color: .green
            ),
            DocCallout(
                number: 3,
                title: "Verified Upstream Authentication",
                subtitle: "httpbin.org/bearer confirms authenticated: true",
                targetRect: CGRect(x: 292, y: 376, width: 696, height: 112),
                badgeCenter: CGPoint(x: 770, y: 532),
                arrowStart: CGPoint(x: 770, y: 511),
                arrowEnd: CGPoint(x: 770, y: 488),
                color: .orange
            )
        ]
        renderView(
            MainContentView(store: storeAuth, initialEditorTab: .auth, initialResponseTab: .body),
            callouts: authCallouts,
            to: "\(docsAssetsDir)/auth_presets.png"
        )

        // 5. Response Diff Engine (LCS Line-by-Line Regression View)
        let storeDiff = PostStore()
        storeDiff.activeTab = .requests
        let diffCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Response Diff Engine",
                subtitle: "Compare current response against prior runs",
                targetRect: CGRect(x: 906, y: 296, width: 84, height: 28),
                badgeCenter: CGPoint(x: 745, y: 256),
                arrowStart: CGPoint(x: 880, y: 277),
                arrowEnd: CGPoint(x: 935, y: 296),
                color: .orange
            ),
            DocCallout(
                number: 2,
                title: "Baseline Snapshot Selector",
                subtitle: "Pick any historical run and inspect +/- line counts",
                targetRect: CGRect(x: 290, y: 332, width: 700, height: 34),
                badgeCenter: CGPoint(x: 790, y: 405),
                arrowStart: CGPoint(x: 790, y: 384),
                arrowEnd: CGPoint(x: 790, y: 366),
                color: .cyan
            ),
            DocCallout(
                number: 3,
                title: "LCS Line-by-Line Highlighting",
                subtitle: "Spots changed email, elevated role, and new tier field",
                targetRect: CGRect(x: 290, y: 448, width: 480, height: 132),
                badgeCenter: CGPoint(x: 770, y: 616),
                arrowStart: CGPoint(x: 685, y: 595),
                arrowEnd: CGPoint(x: 685, y: 580),
                color: .green
            )
        ]
        renderView(
            MainContentView(store: storeDiff, initialEditorTab: .headers, initialResponseTab: .diff),
            callouts: diffCallouts,
            to: "\(docsAssetsDir)/jsonpath_and_diff.png"
        )

        // 6. Local Webhook Server (Captured Payloads + Live Replay + Open in Workbench)
        let store2 = PostStore()
        store2.activeTab = .webhooks
        store2.webhookServer.isRunning = true
        store2.webhookServer.port = 9090
        let webhookCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Embedded NWListener (:9090)",
                subtitle: "Zero-dependency local HTTP webhook listener",
                targetRect: CGRect(x: 700, y: 8, width: 250, height: 34),
                badgeCenter: CGPoint(x: 775, y: 72),
                arrowStart: CGPoint(x: 775, y: 51),
                arrowEnd: CGPoint(x: 775, y: 42),
                color: .green
            ),
            DocCallout(
                number: 2,
                title: "Captured Webhook Stream",
                subtitle: "Inspect client IP, matched status & headers",
                targetRect: CGRect(x: 285, y: 86, width: 272, height: 215),
                badgeCenter: CGPoint(x: 428, y: 345),
                arrowStart: CGPoint(x: 428, y: 324),
                arrowEnd: CGPoint(x: 428, y: 301),
                color: .cyan
            ),
            DocCallout(
                number: 3,
                title: "1-Click Replay & Workbench Export",
                subtitle: "Re-fire to localhost:8080 or edit in Workbench",
                targetRect: CGRect(x: 580, y: 155, width: 405, height: 86),
                badgeCenter: CGPoint(x: 785, y: 282),
                arrowStart: CGPoint(x: 785, y: 261),
                arrowEnd: CGPoint(x: 785, y: 241),
                color: .orange
            )
        ]
        renderView(
            MainContentView(store: store2, initialWebhookMode: .payloads),
            callouts: webhookCallouts,
            to: "\(docsAssetsDir)/webhook_listener.png"
        )
        renderView(
            MainContentView(store: store2, initialWebhookMode: .payloads),
            callouts: webhookCallouts,
            to: "\(docsAssetsDir)/webhook_listener_running.png"
        )

        // 7. Webhook Mock Rules, Latency Injection & Auto-Forwarding
        let storeMock = PostStore()
        storeMock.activeTab = .webhooks
        storeMock.webhookServer.isRunning = true
        let mockRuleCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Mock & Forwarding Rules Engine",
                subtitle: "Match webhook paths and return custom HTTP codes",
                targetRect: CGRect(x: 295, y: 50, width: 342, height: 32),
                badgeCenter: CGPoint(x: 816, y: 66),
                arrowStart: CGPoint(x: 652, y: 66),
                arrowEnd: CGPoint(x: 637, y: 66),
                color: .cyan
            ),
            DocCallout(
                number: 2,
                title: "Route Prefix & Status Preset",
                subtitle: "Return 200 OK, 202 Queued, 429 or 503",
                targetRect: CGRect(x: 285, y: 86, width: 272, height: 225),
                badgeCenter: CGPoint(x: 416, y: 355),
                arrowStart: CGPoint(x: 416, y: 334),
                arrowEnd: CGPoint(x: 416, y: 311),
                color: .orange
            ),
            DocCallout(
                number: 3,
                title: "Artificial Latency & Live Auto-Forward",
                subtitle: "Inject delay (ms) and mirror payloads locally",
                targetRect: CGRect(x: 584, y: 345, width: 402, height: 150),
                badgeCenter: CGPoint(x: 785, y: 536),
                arrowStart: CGPoint(x: 785, y: 515),
                arrowEnd: CGPoint(x: 785, y: 495),
                color: .purple
            )
        ]
        renderView(
            MainContentView(store: storeMock, initialWebhookMode: .mockRules),
            callouts: mockRuleCallouts,
            to: "\(docsAssetsDir)/webhook_mock_rules.png"
        )

        // 8. MCP Inspector (SSE + Stdio + Schema Form + Local Config Discovery)
        let store3 = PostStore()
        store3.activeTab = .mcp
        let sampleMCPResult = """
        {
          "node": "router-gw-01.homelab.local",
          "interface": "br-lan",
          "status": "online",
          "uptime_seconds": 1429840,
          "cpu_load_1m": 0.14,
          "memory_used_mb": 412,
          "memory_total_mb": 2048,
          "temperature_c": 46.5
        }
        """
        let mcpCallouts: [DocCallout] = [
            DocCallout(
                number: 1,
                title: "Dual Transport & 1-Click Config Import",
                subtitle: "Connect via HTTP/SSE or Stdio & import MCP configs",
                targetRect: CGRect(x: 430, y: 8, width: 560, height: 34),
                badgeCenter: CGPoint(x: 765, y: 72),
                arrowStart: CGPoint(x: 765, y: 51),
                arrowEnd: CGPoint(x: 765, y: 42),
                color: .cyan
            ),
            DocCallout(
                number: 2,
                title: "Tools, Resources & Prompts",
                subtitle: "JSON-RPC 2.0 tools/list, resources & prompts",
                targetRect: CGRect(x: 285, y: 48, width: 268, height: 220),
                badgeCenter: CGPoint(x: 406, y: 315),
                arrowStart: CGPoint(x: 406, y: 294),
                arrowEnd: CGPoint(x: 406, y: 268),
                color: .orange
            ),
            DocCallout(
                number: 3,
                title: "Auto-Generated Schema Form",
                subtitle: "Interactive fields & toggles from inputSchema",
                targetRect: CGRect(x: 562, y: 120, width: 428, height: 185),
                badgeCenter: CGPoint(x: 785, y: 350),
                arrowStart: CGPoint(x: 785, y: 329),
                arrowEnd: CGPoint(x: 785, y: 305),
                color: .green
            ),
            DocCallout(
                number: 4,
                title: "Live JSON-RPC Execution Output",
                subtitle: "Formatted JSON result, latency & History log",
                targetRect: CGRect(x: 562, y: 400, width: 428, height: 225),
                badgeCenter: CGPoint(x: 395, y: 515),
                arrowStart: CGPoint(x: 540, y: 515),
                arrowEnd: CGPoint(x: 562, y: 515),
                color: .purple
            )
        ]
        renderView(
            MainContentView(store: store3, initialMCPResultText: sampleMCPResult),
            callouts: mcpCallouts,
            to: "\(docsAssetsDir)/mcp_inspector.png"
        )
    }

    @MainActor
    @Test("Environment Variable Interpolation & Keychain Secrets")
    func testEnvironmentInterpolationAndPersistence() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storageFile = tempDir.appendingPathComponent("workspace.json")

        let store = PostStore(storageURL: storageFile, loadFromDisk: false)
        KeychainHelper.shared.setSecret("super-secret-token-99", forKey: "api_token")
        KeychainHelper.shared.setOnePasswordCache("1p-resolved-ha-token", forReference: "op://HomeLab/Home Assistant/token")
        KeychainHelper.shared.setOnePasswordCache("1p-inline-cf-token", forReference: "op://HomeLab/Cloudflare/api_token")

        let env = PostEnvironment(
            name: "Staging",
            variables: [
                EnvironmentVariable(key: "base_url", value: "https://staging.example.com", isSecret: false, isEnabled: true),
                EnvironmentVariable(key: "api_token", value: "", isSecret: true, isEnabled: true),
                EnvironmentVariable(key: "ha_token", value: "op://HomeLab/Home Assistant/token", isSecret: false, isEnabled: true)
            ]
        )
        store.environments = [env]
        store.selectedEnvironmentID = env.id

        let req = HTTPRequest(
            name: "Chained Request",
            method: .get,
            url: "{{base_url}}/v1/profile",
            headers: [
                KeyValueItem(key: "X-HA-Token", value: "{{ha_token}}", isEnabled: true),
                KeyValueItem(key: "X-CF-Token", value: "{{op://HomeLab/Cloudflare/api_token}}", isEnabled: true)
            ],
            auth: AuthConfig(type: .bearer, bearerToken: "{{api_token}}")
        )
        let resolved = store.resolvedRequest(req)
        #expect(resolved.url == "https://staging.example.com/v1/profile")
        #expect(resolved.auth.bearerToken == "super-secret-token-99")
        #expect(resolved.headers.first(where: { $0.key == "X-HA-Token" })?.value == "1p-resolved-ha-token")
        #expect(resolved.headers.first(where: { $0.key == "X-CF-Token" })?.value == "1p-inline-cf-token")

        store.saveToDisk()
        let reloadedStore = PostStore(storageURL: storageFile, loadFromDisk: true)
        #expect(reloadedStore.environments.contains(where: { $0.name == "Staging" }))
    }

    @Test("Multi-Language Code Generator, JSONPath Evaluator, and Diff Engine")
    func testCodeGenJSONPathAndDiff() {
        let req = HTTPRequest(
            name: "Create Item",
            method: .post,
            url: "https://api.example.com/v1/items",
            headers: [KeyValueItem(key: "X-Custom", value: "abc", isEnabled: true)],
            bodyType: .json,
            bodyText: "{\"name\":\"widget\"}",
            auth: AuthConfig(type: .bearer, bearerToken: "tok_123")
        )

        let goCode = CodeGenerator.generate(for: req, format: .go)
        #expect(goCode.contains("http.NewRequestWithContext"))
        #expect(goCode.contains("Bearer tok_123"))

        let swiftCode = CodeGenerator.generate(for: req, format: .swift)
        #expect(swiftCode.contains("URLSession.shared.data"))

        let pyCode = CodeGenerator.generate(for: req, format: .python)
        #expect(pyCode.contains("httpx.request"))

        let sampleJSON = "{\"data\":{\"items\":[{\"id\":42,\"title\":\"First\"},{\"id\":99,\"title\":\"Second\"}]}}"
        let evaluated = JSONPathEvaluator.evaluate(jsonString: sampleJSON, path: "$.data.items[1].title")
        #expect(evaluated == "Second")

        let diffLines = ResponseDiffEngine.diff(old: "line1\nline2\nline3", new: "line1\nline2_mod\nline3")
        #expect(diffLines.contains(where: { $0.kind == .removed && $0.text == "line2" }))
        #expect(diffLines.contains(where: { $0.kind == .added && $0.text == "line2_mod" }))
    }

    @MainActor
    @Test("MCP Schema Fields Parsing & Stash Auto-Suggest Engine")
    func testMCPSchemaAndAutoSuggest() {
        let tool = MCPToolInfo(
            name: "search_nodes",
            description: "Search cluster nodes",
            inputSchemaJSON: "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Filter query\"},\"limit\":{\"type\":\"integer\"}},\"required\":[\"query\"]}"
        )
        let fields = tool.schemaFields
        #expect(fields.count == 2)
        #expect(fields.contains(where: { $0.name == "query" && $0.isRequired }))

        let store = PostStore()
        let engine = SearchSuggestionEngine()
        var query = "me"
        var cursor: Int? = nil
        engine.onCursorMoved(query: query, cursor: 2, store: store)

        // Tab with no dropdown opens key suggestions matching "me" -> "method:"
        let handledOpen = engine.onTab(query: &query, pendingCursor: &cursor, store: store)
        #expect(handledOpen == true)
        #expect(engine.isVisible == true)
        #expect(engine.suggestions.first?.text == "method:")

        // Second Tab on single matching key inserts "method:" and chains into value suggestions
        let handledInsert = engine.onTab(query: &query, pendingCursor: &cursor, store: store)
        #expect(handledInsert == true)
        #expect(query == "method:")
        #expect(engine.suggestions.contains(where: { $0.text == "POST" }))
    }

    @Test("Syntax highlighting, Slash commands, and VimModeController default-off behavior")
    @MainActor
    func testSyntaxHighlightingAndVimSlashEditor() {
        // 1. VimModeController always starts in standard mode (VIM=OFF), even when Vim support is enabled in Settings
        let vimController = VimModeController()
        #expect(vimController.currentMode == .standard)
        #expect(vimController.isVimActive == false)
        #expect(vimController.modeLabel == "")

        vimController.enableVim()
        #expect(vimController.currentMode == .vim)
        #expect(vimController.isVimActive == true)
        #expect(vimController.modeLabel == "VIM:N")

        vimController.disableVim()
        #expect(vimController.currentMode == .standard)
        #expect(vimController.isVimActive == false)

        // Verify dynamic first-line exclusion path on VimHostTextView when Vim mode toggles and field resizes
        let storage = NSTextStorage(string: String(repeating: "asdf ", count: 40))
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 500, height: 1000))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let hostTV = VimHostTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 140), textContainer: container)
        hostTV.textContainerInset = NSSize(width: 8, height: 8)
        hostTV.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        hostTV.vimController = vimController
        vimController.activeTextView = hostTV

        // Standard mode: no exclusion path, first line uses full container width
        hostTV.updateExclusionPaths()
        layoutManager.ensureLayout(for: container)
        #expect(container.exclusionPaths.isEmpty == true)
        let standardLine1 = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)

        // Enable Vim mode: top-right exclusion path dynamically carved out so line 1 has fewer columns
        vimController.enableVim()
        layoutManager.ensureLayout(for: container)
        #expect(container.exclusionPaths.count == 1)
        var line1GlyphRange = NSRange()
        let vimLine1 = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &line1GlyphRange)
        let vimLine2 = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(line1GlyphRange), effectiveRange: nil)
        #expect(vimLine1.width < standardLine1.width - 90)
        #expect(vimLine2.width > vimLine1.width + 90)

        // Resize field: first line width dynamically grows with the new field width while keeping badge clearance
        hostTV.setFrameSize(NSSize(width: 640, height: 140))
        layoutManager.ensureLayout(for: container)
        let resizedVimLine1 = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(resizedVimLine1.width > vimLine1.width + 100)

        // Disable Vim mode: exclusion path cleared
        vimController.disableVim()
        #expect(container.exclusionPaths.isEmpty == true)

        // 2. Slash commands filter by prefix and respect vimEnabled setting
        let allWithVim = SlashCommand.match(for: "/", vimEnabled: true)
        #expect(allWithVim.contains(where: { $0.trigger == "/vim" }))
        #expect(allWithVim.contains(where: { $0.trigger == "/json" }))
        #expect(allWithVim.contains(where: { $0.trigger == "/pretty" }))

        let withoutVim = SlashCommand.match(for: "/", vimEnabled: false)
        #expect(!withoutVim.contains(where: { $0.trigger == "/vim" }))
        #expect(withoutVim.contains(where: { $0.trigger == "/json" }))

        let jsonOnly = SlashCommand.match(for: "/js", vimEnabled: true)
        #expect(jsonOnly.count == 1)
        #expect(jsonOnly.first?.trigger == "/json")

        // 3. JSONHighlighter & BashHighlighter produce non-empty attributed strings
        let sampleJSON = """
        {
          "endpoint": "{{base_url}}/v1/status",
          "secret": "op://Private/Token/credential",
          "count": 42,
          "active": true
        }
        """
        let highlightedJSON = JSONHighlighter.highlightedString(sampleJSON, enabled: true)
        #expect(String(highlightedJSON.characters).contains("{{base_url}}"))

        let sampleBash = "curl -X POST '{{base_url}}/webhook' -H 'Authorization: Bearer op://Vault/Item/token'"
        let highlightedBash = BashHighlighter.highlightedString(sampleBash, enabled: true)
        #expect(String(highlightedBash.characters).contains("curl"))
    }

    @MainActor
    private func assertNoCalloutOverlaps(callouts: [DocCallout], size: CGSize, path: String) {
        let canvasBounds = CGRect(origin: .zero, size: size)
        for i in callouts.indices {
            let c1 = callouts[i]
            let b1 = c1.estimatedBadgeRect
            // Badge must stay completely inside canvas bounds
            #expect(canvasBounds.contains(b1), "Callout #\(c1.number) badge \(b1) out of bounds in \(path)")
            // Badge must never overlap its own target highlight rect
            #expect(!b1.intersects(c1.targetRect), "Callout #\(c1.number) badge \(b1) overlaps its own targetRect \(c1.targetRect) in \(path)")

            for j in callouts.indices where j > i {
                let c2 = callouts[j]
                let b2 = c2.estimatedBadgeRect
                // Highlight target rects must not overlap each other
                #expect(!c1.targetRect.intersects(c2.targetRect), "Highlight #\(c1.number) overlaps Highlight #\(c2.number) in \(path)")
                // Callout badges must not overlap each other
                #expect(!b1.intersects(b2), "Badge #\(c1.number) (\(b1)) overlaps Badge #\(c2.number) (\(b2)) in \(path)")
                // Callout badge i must not overlap highlight target j and vice versa
                #expect(!b1.intersects(c2.targetRect), "Badge #\(c1.number) (\(b1)) overlaps Highlight #\(c2.number) (\(c2.targetRect)) in \(path)")
                #expect(!b2.intersects(c1.targetRect), "Badge #\(c2.number) (\(b2)) overlaps Highlight #\(c1.number) (\(c1.targetRect)) in \(path)")
            }
        }
    }

    @MainActor
    private func renderView<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 1000, height: 650),
        callouts: [DocCallout] = [],
        to path: String
    ) {
        assertNoCalloutOverlaps(callouts: callouts, size: size, path: path)

        let darkAppearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.appearance = darkAppearance

        let wrapped = AnnotatedScreenshotCanvas(size: size, callouts: callouts) {
            view
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = darkAppearance
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)

        let hostingView = NSHostingView(rootView: wrapped)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = darkAppearance
        window.contentView = hostingView

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        applyDarkThemeToAppKitSubviews(hostingView, appearance: darkAppearance)
        hostingView.layoutSubtreeIfNeeded()

        darkAppearance?.performAsCurrentDrawingAppearance {
            if let imageRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: imageRep)
                if let pngData = imageRep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: URL(fileURLWithPath: path))
                }
            }
        }

        if !callouts.isEmpty && path.hasSuffix(".png") {
            renderView(view, size: size, callouts: [], to: String(path.dropLast(4)) + "_clean.png")
        }
    }

    @MainActor
    private func applyDarkThemeToAppKitSubviews(_ view: NSView, appearance: NSAppearance?) {
        view.appearance = appearance
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            scrollView.contentView.drawsBackground = true
            scrollView.contentView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        }
        if let tableView = view as? NSTableView {
            tableView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        }
        for sub in view.subviews {
            applyDarkThemeToAppKitSubviews(sub, appearance: appearance)
        }
    }
}

struct DocCallout: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let subtitle: String
    let targetRect: CGRect
    let badgeCenter: CGPoint
    let arrowStart: CGPoint
    let arrowEnd: CGPoint
    let color: Color

    var estimatedBadgeRect: CGRect {
        let textWidth = max(CGFloat(title.count) * 6.8, CGFloat(subtitle.count) * 5.6)
        let width = max(240, textWidth + 54)
        let height: CGFloat = 42
        return CGRect(
            x: badgeCenter.x - width / 2,
            y: badgeCenter.y - height / 2,
            width: width,
            height: height
        )
    }
}

struct AnnotatedScreenshotCanvas<Content: View>: View {
    let size: CGSize
    let callouts: [DocCallout]
    let content: Content

    init(size: CGSize, callouts: [DocCallout], @ViewBuilder content: () -> Content) {
        self.size = size
        self.callouts = callouts
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: size.width, height: size.height)
                .background(Color(red: 0.11, green: 0.11, blue: 0.13))

            ForEach(callouts) { callout in
                // 1. Highlight Target Rectangle (Zero interior fill shading so highlighted content stays 100% readable)
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.black.opacity(0.65), lineWidth: 4.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(callout.color, lineWidth: 2.2)
                    )
                    .frame(width: callout.targetRect.width, height: callout.targetRect.height)
                    .position(x: callout.targetRect.midX, y: callout.targetRect.midY)

                // 2. Leader Arrow Line + Arrowhead
                Canvas { context, _ in
                    var linePath = Path()
                    linePath.move(to: callout.arrowStart)
                    linePath.addLine(to: callout.arrowEnd)

                    context.stroke(
                        linePath,
                        with: .color(.black.opacity(0.75)),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    context.stroke(
                        linePath,
                        with: .color(callout.color),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )

                    // Origin dot
                    let dotRect = CGRect(
                        x: callout.arrowStart.x - 3.5,
                        y: callout.arrowStart.y - 3.5,
                        width: 7,
                        height: 7
                    )
                    context.fill(Path(ellipseIn: dotRect), with: .color(callout.color))

                    // Directional arrowhead at arrowEnd
                    let dx = callout.arrowEnd.x - callout.arrowStart.x
                    let dy = callout.arrowEnd.y - callout.arrowStart.y
                    let angle = atan2(dy, dx)
                    let headLength: CGFloat = 10.0
                    let headAngle: CGFloat = .pi / 6.0

                    let p1 = CGPoint(
                        x: callout.arrowEnd.x - headLength * cos(angle - headAngle),
                        y: callout.arrowEnd.y - headLength * sin(angle - headAngle)
                    )
                    let p2 = CGPoint(
                        x: callout.arrowEnd.x - headLength * cos(angle + headAngle),
                        y: callout.arrowEnd.y - headLength * sin(angle + headAngle)
                    )

                    var headPath = Path()
                    headPath.move(to: callout.arrowEnd)
                    headPath.addLine(to: p1)
                    headPath.addLine(to: p2)
                    headPath.closeSubpath()

                    context.fill(headPath, with: .color(callout.color))
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                // 3. Callout Pill Card
                HStack(spacing: 8) {
                    Text("\(callout.number)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(callout.color, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(callout.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(callout.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.82))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(callout.color.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.65), radius: 8, y: 3)
                .fixedSize()
                .position(callout.badgeCenter)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

