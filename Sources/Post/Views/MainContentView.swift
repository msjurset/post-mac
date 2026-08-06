import SwiftUI

struct MainContentView: View {
    @StateObject private var store = PostStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            detailView
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
                    Divider()
                    ResponseView(response: store.activeResponse)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No Request Selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button("Create New Request") {
                        store.createNewRequest()
                    }
                    .focusable(false)
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
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

                ResponseView(response: store.activeResponse)
            }
        }
    }
}
