import AppKit
import SwiftUI
@testable import Post

@MainActor
func renderAndSave<V: View>(_ view: V, width: CGFloat, height: CGFloat, to path: String) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(x: 0, y: 0, width: width, height: height)
    
    hostingView.layoutSubtreeIfNeeded()
    
    let imageRepresentation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
    hostingView.cacheDisplay(in: hostingView.bounds, to: imageRepresentation)
    
    if let pngData = imageRepresentation.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: path))
        print("Saved \(path)")
    }
}

@MainActor
func main() {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(atPath: "docs/assets", withIntermediateDirectories: true)

    // 1. HTTP Workbench View
    let store1 = PostStore()
    store1.activeTab = .requests
    let reqView = MainContentView(store: store1)
    renderAndSave(reqView, width: 1000, height: 650, to: "docs/assets/http_workbench.png")

    // 2. Webhook Listener View
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
    let webhookView = MainContentView(store: store2)
    renderAndSave(webhookView, width: 1000, height: 650, to: "docs/assets/webhook_listener.png")

    // 3. MCP Inspector View
    let store3 = PostStore()
    store3.activeTab = .mcp
    let mcpView = MainContentView(store: store3)
    renderAndSave(mcpView, width: 1000, height: 650, to: "docs/assets/mcp_inspector.png")
}

main()
