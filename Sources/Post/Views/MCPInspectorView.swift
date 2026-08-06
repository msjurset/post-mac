import SwiftUI

struct MCPInspectorView: View {
    @ObservedObject var store: PostStore
    @State private var endpointInput: String = "http://localhost:8000/sse"
    @State private var serverNameInput: String = "Local MCP Server"
    @State private var toolsList: [MCPToolInfo] = []
    @State private var selectedToolName: String?
    @State private var toolArgsJSON: String = "{\n  \n}"
    @State private var isFetchingTools: Bool = false
    @State private var isExecutingTool: Bool = false
    @State private var toolResultText: String = ""
    @State private var toolResultError: Bool = false
    @State private var executionDurationMs: Double = 0.0

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
                .frame(width: 260)

                Divider()

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
                                HStack {
                                    if isExecutingTool {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                    Text("Execute Tool")
                                }
                            }
                            .focusable(false)
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
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
                                Text(toolResultText.isEmpty ? "No execution result yet." : toolResultText)
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
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "cpu")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No tool selected")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Connect to an MCP server and select a tool from the list to test JSON-RPC tool calls.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func fetchTools() async {
        isFetchingTools = true
        toolsList.removeAll()
        selectedToolName = nil

        do {
            let fetched = try await MCPClient.shared.fetchTools(endpoint: endpointInput)
            toolsList = fetched
            selectedToolName = fetched.first?.name
        } catch {
            toolResultText = "Error fetching tools: \(error.localizedDescription)"
            toolResultError = true
        }

        isFetchingTools = false
    }

    private func callTool(name: String) async {
        isExecutingTool = true
        toolResultText = ""

        do {
            let (res, isErr, ms) = try await MCPClient.shared.callTool(endpoint: endpointInput, name: name, argumentsJSON: toolArgsJSON)
            toolResultText = res
            toolResultError = isErr
            executionDurationMs = ms
        } catch {
            toolResultText = "Error executing tool: \(error.localizedDescription)"
            toolResultError = true
        }

        isExecutingTool = false
    }
}
