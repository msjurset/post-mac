import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: PostStore
    @State private var showingCURLImportSheet: Bool = false
    @State private var curlInputText: String = ""
    @StateObject private var suggestionEngine = SearchSuggestionEngine()
    @State private var pendingCursor: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar with Stash-Model Auto-Suggest Dropdown
            ZStack(alignment: .topLeading) {
                FilterField(
                    placeholder: store.activeTab == .history ? "Filter (method:POST status:200)..." : "Search requests...",
                    text: $store.searchQuery,
                    onCommit: {
                        suggestionEngine.onCommit(
                            query: &store.searchQuery,
                            pendingCursor: &pendingCursor,
                            store: store
                        )
                    },
                    focusTrigger: store.focusSearchTrigger,
                    pendingCursor: $pendingCursor,
                    style: .plain,
                    onSelectionChanged: { loc in
                        suggestionEngine.onCursorMoved(
                            query: store.searchQuery,
                            cursor: loc,
                            store: store
                        )
                    },
                    onUpArrow: {
                        suggestionEngine.onUpArrow()
                    },
                    onDownArrow: {
                        suggestionEngine.onDownArrow()
                    },
                    onTab: {
                        suggestionEngine.onTab(
                            query: &store.searchQuery,
                            pendingCursor: &pendingCursor,
                            store: store
                        )
                    },
                    onShiftTab: {
                        suggestionEngine.onShiftTab()
                    }
                )
                .onChange(of: store.searchQuery) { _, newQuery in
                    suggestionEngine.onQueryChanged(query: newQuery, store: store)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .overlay(alignment: .topLeading) {
                if suggestionEngine.isVisible && !suggestionEngine.suggestions.isEmpty {
                    SearchSuggestionDropdownView(
                        engine: suggestionEngine,
                        onSelect: { item in
                            suggestionEngine.commit(
                                item: item,
                                in: &store.searchQuery,
                                pendingCursor: &pendingCursor,
                                store: store
                            )
                        }
                    )
                    .padding(.top, 38)
                    .padding(.horizontal, 10)
                    .zIndex(999)
                }
            }
            .onExitCommand {
                suggestionEngine.dismiss()
            }

            // Horizontal Pill Filter Bar
            pillTabBar

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
        .sheet(isPresented: $store.showingEnvironmentSheet) {
            EnvironmentManagerSheet(store: store)
        }
        .sheet(isPresented: $store.showingSettingsSheet) {
            SettingsSheet(store: store)
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
        List(selection: $store.selectedHistoryItemID) {
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
                .tag(item.id)
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
                .contextMenu {
                    Button("Delete Server") {
                        store.mcpServers.removeAll(where: { $0.id == server.id })
                        if store.selectedMCPServerID == server.id {
                            store.selectedMCPServerID = store.mcpServers.first?.id
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var bottomActionInset: some View {
        VStack(spacing: 0) {
            Divider()

            // Environment Indicator & Switcher
            HStack(spacing: 6) {
                let activeEnv = store.environments.first(where: { $0.id == store.selectedEnvironmentID })
                Button(action: {
                    store.showingEnvironmentSheet = true
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activeEnv != nil ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)

                        Text(activeEnv?.name ?? "No Environment")
                            .font(.caption)
                            .foregroundStyle(activeEnv != nil ? Color.primary : Color.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Manage Environments & Secrets (⌘E)")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)

            HStack(spacing: 8) {
                // Settings Cog in Bottom-Left
                Button(action: {
                    store.showingSettingsSheet = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Editor Settings: Slash Commands, Vim Mode & Syntax Highlighting (⌘,)")

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
                } else if store.activeTab == .mcp {
                    Button(action: {
                        let newServer = MCPServer(
                            name: "New MCP Server",
                            endpoint: "http://localhost:8000/sse",
                            type: .sse,
                            tools: []
                        )
                        store.mcpServers.append(newServer)
                        store.selectedMCPServerID = newServer.id
                    }) {
                        Label("New Server", systemImage: "plus")
                    }
                    .focusable(false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(10)
        }
        .background(.bar)
    }

    private var pillTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PostStore.SidebarTab.allCases) { tab in
                    AnimatedTabPill(
                        title: tab.rawValue,
                        iconName: tab.iconName,
                        description: tab.description,
                        isSelected: store.activeTab == tab,
                        action: {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.activeTab = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var curlImportSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import cURL Command")
                .font(.headline)

            Text("Paste your raw cURL command line string below:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VimAwareEditor(
                text: $curlInputText,
                placeholder: "curl -X POST https://api.example.com/data -H 'Content-Type: application/json' -d '{\"key\":\"val\"}'",
                language: .bash,
                minHeight: 120,
                enableSlashCommands: store.enableSlashCommands,
                enableVimEditor: store.enableVimEditor,
                enableSyntaxHighlighting: store.enableSyntaxHighlighting
            )

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
        .frame(minWidth: 540, idealWidth: 540, minHeight: 280)
    }
}

struct AnimatedTabPill: View {
    let title: String
    let iconName: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                Image(systemName: iconName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))

                if !isSelected && isHovering {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, isSelected || isHovering ? 10 : 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .help(description)
    }
}
