import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: PostStore
    @State private var showingCURLImportSheet: Bool = false
    @State private var curlInputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker Header
            Picker("Tab", selection: $store.activeTab) {
                ForEach(PostStore.SidebarTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)

            // Search Bar
            FilterField(
                placeholder: store.activeTab == .history ? "Filter (method:POST status:200)..." : "Search requests...",
                text: $store.searchQuery,
                style: .plain
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            // Content List based on active tab
            Group {
                switch store.activeTab {
                case .requests:
                    requestListView
                case .webhooks:
                    webhookSidebarView
                case .mcp:
                    mcpSidebarView
                case .history:
                    historyListView
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionInset
        }
        .sheet(isPresented: $showingCURLImportSheet) {
            curlImportSheet
        }
    }

    private var requestListView: some View {
        List(selection: $store.selectedRequestID) {
            ForEach(store.filteredRequests) { req in
                HStack(spacing: 8) {
                    MethodBadge(method: req.method)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(req.name.isEmpty ? req.url : req.name)
                            .font(.body)
                            .lineLimit(1)
                        Text(req.url)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(req.id)
                .contextMenu {
                    Button("Delete") {
                        store.deleteRequest(id: req.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var historyListView: some View {
        List {
            ForEach(store.filteredHistory) { item in
                HStack(spacing: 8) {
                    MethodBadge(method: HTTPMethod(rawValue: item.method) ?? .get)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let code = item.statusCode {
                        StatusCodeBadge(code: code)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
    }

    private var webhookSidebarView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Webhook Listener")
                    .font(.headline)
                Spacer()
                Text(store.webhookServer.isRunning ? "RUNNING" : "STOPPED")
                    .font(.caption2.bold())
                    .foregroundStyle(store.webhookServer.isRunning ? Color.green : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((store.webhookServer.isRunning ? Color.green : Color.gray).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            List(store.webhookServer.payloads) { payload in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(payload.method)
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        Text(payload.path)
                            .font(.caption)
                            .monospaced()
                        Spacer()
                        Text(payload.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !payload.body.isEmpty {
                        Text(payload.body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
        }
    }

    private var mcpSidebarView: some View {
        List(selection: $store.selectedMCPServerID) {
            ForEach(store.mcpServers) { server in
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.body)
                        Text(server.endpoint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(server.id)
            }
        }
        .listStyle(.sidebar)
    }

    private var bottomActionInset: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if store.activeTab == .requests {
                    Button(action: {
                        store.createNewRequest()
                    }) {
                        Label("New Request", systemImage: "plus")
                    }
                    .focusable(false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        curlInputText = ""
                        showingCURLImportSheet = true
                    }) {
                        Label("cURL", systemImage: "square.and.arrow.down")
                    }
                    .focusable(false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if store.activeTab == .webhooks {
                    if store.webhookServer.isRunning {
                        Button(action: { store.webhookServer.stop() }) {
                            Label("Stop Server", systemImage: "stop.fill")
                        }
                        .focusable(false)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Button(action: { store.webhookServer.start() }) {
                            Label("Start Listener", systemImage: "play.fill")
                        }
                        .focusable(false)
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        .controlSize(.small)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
    }

    private var curlImportSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import cURL Command")
                .font(.headline)

            Text("Paste your raw cURL command line string below:")
                .font(.caption)
                .foregroundStyle(.secondary)

            FilterField(
                placeholder: "curl -X POST https://api.example.com/data -H 'Content-Type: application/json' -d '{\"key\":\"val\"}'",
                text: $curlInputText,
                multiline: true,
                alignment: .left
            )
            .frame(height: 120)

            HStack {
                Spacer()
                Button("Cancel") {
                    showingCURLImportSheet = false
                }
                .focusable(false)

                Button("Import") {
                    store.importCURL(curlCommand: curlInputText)
                    showingCURLImportSheet = false
                }
                .focusable(false)
                .buttonStyle(.borderedProminent)
                .disabled(curlInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 260)
    }
}
