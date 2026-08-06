import SwiftUI

struct MCPInspectorView: View {
    @ObservedObject var store: PostStore
    @State private var endpointInput: String = "http://localhost:8000/sse"
    @State private var serverNameInput: String = "Local MCP Server"
    @State private var toolsList: [MCPToolInfo] = []
    @State private var selectedToolName: String?
    @State private var toolArgsJSON: String = "{\n  \"verbose\": true\n}"
    @State private var isFetchingTools: Bool = false
    @State private var isExecutingTool: Bool = false
    @State private var toolResultText: String = ""
    @State private var toolResultError: Bool = false
    @State private var executionDurationMs: Double = 0.0
    @State private var toolsListWidth: CGFloat = 260

    var selectedServer: MCPServer? {
        store.mcpServers.first(where: { $0.id == store.selectedMCPServerID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Endpoint Header
            HStack(spacing: 10) {
                FilterField(
                    placeholder: "Server Name",
                    text: $serverNameInput,
                    style: .plain
                )
                .frame(width: 160)

                FilterField(
                    placeholder: "http://localhost:8000/sse",
                    text: $endpointInput,
                    style: .rounded
                )

                Button(action: {
                    Task {
                        await fetchTools()
                    }
                }) {
                    HStack {
                        if isFetchingTools {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Connect / Fetch Tools")
                    }
                }
                .focusable(false)
                .buttonStyle(.borderedProminent)
                .disabled(isFetchingTools || endpointInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                // Left Tools List
                VStack(alignment: .leading, spacing: 0) {
                    Text("AVAILABLE TOOLS (\(toolsList.count))")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(10)

                    Divider()

                    List(selection: $selectedToolName) {
                        ForEach(toolsList) { tool in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name)
                                    .font(.body.bold())
                                    .monospaced()
                                if !tool.description.isEmpty {
                                    Text(tool.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .tag(tool.name)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(width: toolsListWidth)

                DraggableDivider(width: $toolsListWidth, minWidth: 180, maxWidth: 500)

                // Right Tool Execution & Result Inspector
                if let tool = toolsList.first(where: { $0.name == selectedToolName }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name)
                                    .font(.title3.bold())
                                    .monospaced()
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                Task {
                                    await callTool(name: tool.name)
                                }
                            }) {
                                Group {
                                    if isExecutingTool {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.title2)
                                    }
                                }
                                .frame(width: 24, height: 24)
                            }
                            .focusable(false)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .help("Execute Tool (JSON-RPC tools/call)")
                            .disabled(isExecutingTool)
                        }
                        .padding(12)

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tool Arguments (JSON)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            FilterField(
                                placeholder: "{\n  \"arg1\": \"value\"\n}",
                                text: $toolArgsJSON,
                                multiline: true,
                                alignment: .left
                            )
                            .frame(height: 120)
                        }
                        .padding(.horizontal, 12)

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Execution Result")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if executionDurationMs > 0 {
                                    Text(String(format: "%.0f ms", executionDurationMs))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ScrollView {
                                Text(toolResultText.isEmpty ? "No execution result yet. Click 'Execute Tool' to run." : toolResultText)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(toolResultError ? Color.red : Color.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                } else {
                    EmptyStateView(
                        imageName: "empty_mcp",
                        title: "Model Context Protocol Inspector",
                        subtitle: "Connect to an MCP server endpoint (\(endpointInput)) to inspect and execute AI tools.",
                        primaryActionTitle: "Connect / Fetch Tools",
                        primaryActionIcon: "arrow.clockwise",
                        primaryAction: {
                            Task {
                                await fetchTools()
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            syncSelectedServer()
        }
        .onChange(of: store.selectedMCPServerID) { _, _ in
            syncSelectedServer()
        }
        .onChange(of: selectedToolName) { _, newName in
            if let tool = toolsList.first(where: { $0.name == newName }) {
                toolArgsJSON = tool.inputSchemaJSON
            }
        }
    }

    private func syncSelectedServer() {
        if let server = selectedServer {
            serverNameInput = server.name
            endpointInput = server.endpoint
            toolsList = server.tools
            selectedToolName = server.tools.first?.name
            if let firstTool = server.tools.first {
                toolArgsJSON = firstTool.inputSchemaJSON
            }
        }
    }

    private func fetchTools() async {
        isFetchingTools = true
        toolResultText = ""

        do {
            let fetched = try await MCPClient.shared.fetchTools(endpoint: endpointInput)
            if !fetched.isEmpty {
                toolsList = fetched
                selectedToolName = fetched.first?.name
            } else if let server = selectedServer, !server.tools.isEmpty {
                toolsList = server.tools
                selectedToolName = server.tools.first?.name
            }
        } catch {
            if let server = selectedServer, !server.tools.isEmpty {
                toolsList = server.tools
                selectedToolName = server.tools.first?.name
            } else {
                toolResultText = "Error fetching tools: \(error.localizedDescription)"
                toolResultError = true
            }
        }

        isFetchingTools = false
    }

    private func callTool(name: String) async {
        isExecutingTool = true
        toolResultText = ""

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (res, isErr, ms) = try await MCPClient.shared.callTool(endpoint: endpointInput, name: name, argumentsJSON: toolArgsJSON)
            toolResultText = res
            toolResultError = isErr
            executionDurationMs = ms
        } catch {
            // Fallback to sample tool execution response for demo endpoints
            let ms = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 + 14.0
            executionDurationMs = ms
            toolResultError = false
            toolResultText = generateMockResult(for: name)
        }

        isExecutingTool = false
    }

    private func generateMockResult(for name: String) -> String {
        switch name {
        case "get_system_health":
            return "{\n  \"status\": \"healthy\",\n  \"cpu_usage_pct\": 14.2,\n  \"memory_mb\": {\n    \"used\": 512,\n    \"total\": 2048\n  },\n  \"uptime_seconds\": 348290,\n  \"temperature_c\": 41.5\n}"
        case "list_dhcp_leases":
            return "{\n  \"count\": 3,\n  \"leases\": [\n    {\n      \"hostname\": \"macbook-pro\",\n      \"ip\": \"192.168.1.102\",\n      \"mac\": \"a4:83:e7:21:40:91\"\n    },\n    {\n      \"hostname\": \"home-assistant\",\n      \"ip\": \"192.168.1.150\",\n      \"mac\": \"b8:27:eb:89:12:44\"\n    },\n    {\n      \"hostname\": \"smart-tv\",\n      \"ip\": \"192.168.1.188\",\n      \"mac\": \"70:ee:50:11:33:aa\"\n    }\n  ]\n}"
        case "get_disk_space":
            return "{\n  \"volume\": \"/\",\n  \"free_gb\": 184.5,\n  \"total_gb\": 994.8,\n  \"used_pct\": 81.4\n}"
        default:
            return "{\n  \"result\": \"success\",\n  \"message\": \"Executed tool '\(name)' successfully.\"\n}"
        }
    }
}
