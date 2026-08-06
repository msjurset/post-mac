import Testing
import Foundation
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
}
