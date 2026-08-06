import SwiftUI

struct MainContentView: View {
    @StateObject var store: PostStore
    @State private var sidebarWidth: CGFloat = 280
    @State private var requestPaneHeight: CGFloat = 280
    @State private var isSidebarCollapsed: Bool = false

    init(store: PostStore = PostStore()) {
        _store = StateObject(wrappedValue: store)
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
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.activeTab {
        case .requests:
            if let reqBinding = Binding($store.selectedRequest) {
                VStack(spacing: 0) {
                    RequestBuilderView(store: store, request: reqBinding)
                        .frame(height: requestPaneHeight)
                    DraggableHeightDivider(height: $requestPaneHeight, minHeight: 180, maxHeight: 550)
                    ResponseView(response: store.activeResponse)
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
            WebhookServerView(store: store)
        case .mcp:
            MCPInspectorView(store: store)
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
                    ResponseView(response: item.responseData)
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
}
