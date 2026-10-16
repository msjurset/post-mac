import SwiftUI

struct MainContentView: View {
    @ObservedObject var store: PostStore
    @State private var sidebarWidth: CGFloat = 280
    @State private var requestPaneHeight: CGFloat = 280
    @State private var isSidebarCollapsed: Bool = false

    private let initialEditorTab: RequestBuilderView.EditorTab
    private let initialResponseTab: ResponseView.ResponseTab
    private let initialJSONPath: String
    private let initialWebhookMode: WebhookViewMode
    private let initialMCPResultText: String

    init(
        store: PostStore = PostStore(),
        initialEditorTab: RequestBuilderView.EditorTab = .params,
        initialResponseTab: ResponseView.ResponseTab = .body,
        initialJSONPath: String = "",
        initialWebhookMode: WebhookViewMode = .payloads,
        initialMCPResultText: String = ""
    ) {
        self.store = store
        self.initialEditorTab = initialEditorTab
        self.initialResponseTab = initialResponseTab
        self.initialJSONPath = initialJSONPath
        self.initialWebhookMode = initialWebhookMode
        self.initialMCPResultText = initialMCPResultText
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(store: store)
                    .frame(width: sidebarWidth)

                DraggableDivider(width: $sidebarWidth, minWidth: 200, maxWidth: 420)
            }

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .focusable(false)
                .help("Toggle Sidebar")
            }
        }
        .sheet(isPresented: $store.showingEnvironmentSheet) {
            EnvironmentManagerSheet(store: store)
        }
        .sheet(isPresented: $store.showingSettingsSheet) {
            SettingsSheet(store: store)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.activeTab {
        case .requests:
            if let reqBinding = Binding($store.selectedRequest) {
                VStack(spacing: 0) {
                    RequestBuilderView(store: store, request: reqBinding, initialTab: initialEditorTab)
                        .frame(height: requestPaneHeight)
                    DraggableHeightDivider(height: $requestPaneHeight, minHeight: 180, maxHeight: 550)
                    ResponseView(
                        response: store.activeResponse,
                        previousResponses: store.selectedRequest.map { store.previousResponses(for: $0.id) } ?? [],
                        initialTab: initialResponseTab,
                        initialJSONPath: initialJSONPath,
                        enableSyntaxHighlighting: store.enableSyntaxHighlighting
                    )
                }
            } else {
                EmptyStateView(
                    imageName: "empty_requests",
                    title: "HTTP Workbench",
                    subtitle: "Select an API request from the sidebar or click + New Request to construct headers, parameters, and payloads.",
                    primaryActionTitle: "New Request",
                    primaryActionIcon: "plus",
                    primaryAction: { store.createNewRequest() }
                )
            }
        case .webhooks:
            WebhookServerView(store: store, initialMode: initialWebhookMode)
        case .mcp:
            MCPInspectorView(store: store, initialResultText: initialMCPResultText)
        case .history:
            VStack(spacing: 0) {
                HStack {
                    Text("Activity History")
                        .font(.headline)
                    Spacer()
                    Text("\(store.filteredHistory.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.bar)

                Divider()

                if let item = store.selectedHistoryItem {
                    if item.type == .webhook, let webhook = item.webhookData, item.responseData == nil {
                        webhookHistoryDetailView(webhook: webhook, item: item)
                    } else {
                        ResponseView(
                            response: item.responseData,
                            previousResponses: item.requestData.map { store.previousResponses(for: $0.id) } ?? [],
                            enableSyntaxHighlighting: store.enableSyntaxHighlighting
                        )
                    }
                } else {
                    EmptyStateView(
                        imageName: "empty_history",
                        title: "Activity Execution Log",
                        subtitle: "Select a past execution item to inspect response bodies, timing metrics, and full HTTP headers.",
                        hintText: "Filter queries: method:POST status:200"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func webhookHistoryDetailView(webhook: WebhookPayload, item: HistoryItem) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                MethodBadge(method: HTTPMethod(rawValue: webhook.method) ?? .post)
                Text(webhook.path)
                    .font(.system(.body, design: .monospaced).bold())

                StatusCodeBadge(code: webhook.responseStatusCode)

                if let forwarded = webhook.forwardedTo, !forwarded.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.right")
                        Text(forwarded)
                    }
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "network")
                    Text("From: \(webhook.clientIP)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(webhook.timestamp, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(action: {
                    let curl = webhook.asCURL(port: store.webhookServer.port)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(curl, forType: .string)
                }) {
                    Label("Copy cURL", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
            }
            .padding(10)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !webhook.headers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Incoming Request Headers")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            VStack(spacing: 2) {
                                ForEach(webhook.headers) { h in
                                    HStack(alignment: .top) {
                                        Text(h.key)
                                            .font(.caption.bold())
                                            .monospaced()
                                            .frame(width: 180, alignment: .leading)
                                        Text(h.value)
                                            .font(.caption)
                                            .monospaced()
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                    Divider()
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Webhook Payload Body")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(webhook.body.utf8.count) bytes")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        CodeBlockView(
                            code: webhook.formattedBody.isEmpty ? "(Empty Body)" : webhook.formattedBody,
                            language: .json,
                            showHeader: true,
                            enableSyntaxHighlighting: store.enableSyntaxHighlighting
                        )
                    }
                }
                .padding(14)
            }
        }
    }
}
