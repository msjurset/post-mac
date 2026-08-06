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

        let store1 = PostStore()
        store1.activeTab = .requests
        renderView(MainContentView(store: store1), to: "\(docsAssetsDir)/http_workbench.png")

        let store2 = PostStore()
        store2.activeTab = .webhooks
        store2.webhookServer.isRunning = true
        store2.webhookServer.port = 9090
        store2.webhookServer.payloads = [
            WebhookPayload(
                timestamp: Date(),
                method: "POST",
                path: "/api/v1/webhook",
                headers: [
                    KeyValueItem(key: "Content-Type", value: "application/json"),
                    KeyValueItem(key: "X-Signature-256", value: "sha256=a8f3b2c9d0e1f2a3...")
                ],
                body: "{\n  \"event\": \"payment.succeeded\",\n  \"customer_id\": \"cus_99182\",\n  \"amount\": 4900\n}",
                clientIP: "192.168.1.105"
            )
        ]
        renderView(MainContentView(store: store2), to: "\(docsAssetsDir)/webhook_listener.png")

        let store3 = PostStore()
        store3.activeTab = .mcp
        renderView(MainContentView(store: store3), to: "\(docsAssetsDir)/mcp_inspector.png")
    }

    @MainActor
    private func renderView<V: View>(_ view: V, to path: String) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 1000, height: 650)
        hostingView.layoutSubtreeIfNeeded()
        if let imageRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
            hostingView.cacheDisplay(in: hostingView.bounds, to: imageRep)
            if let pngData = imageRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
