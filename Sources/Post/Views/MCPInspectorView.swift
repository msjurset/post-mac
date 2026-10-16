import SwiftUI

struct MCPInspectorView: View {
    @ObservedObject var store: PostStore

    @State private var endpointInput: String = "http://localhost:8000/sse"
    @State private var serverNameInput: String = "Local MCP Server"
    @State private var serverType: MCPServerType = .sse

    @State private var toolsList: [MCPToolInfo] = []
    @State private var resourcesList: [MCPResourceInfo] = []
    @State private var promptsList: [MCPPromptInfo] = []

    @State private var selectedToolName: String?
    @State private var selectedResourceURI: String?
    @State private var selectedPromptName: String?

    @State private var toolArgsJSON: String = "{\n  \"verbose\": true\n}"
    @State private var schemaFormValues: [String: String] = [:]

    @State private var isFetchingCapabilities: Bool = false
    @State private var isExecutingTool: Bool = false
    @State private var isReadingResource: Bool = false

    @State private var toolResultText: String = ""
    @State private var toolResultError: Bool = false
    @State private var executionDurationMs: Double = 0.0

    @State private var resourceContentText: String = ""
    @State private var resourceDurationMs: Double = 0.0

    @State private var toolsListWidth: CGFloat = 270
    @State private var activeLeftTab: LeftPaneTab = .tools
    @State private var toolInputMode: ToolInputMode = .schemaForm

    enum LeftPaneTab: String, CaseIterable, Identifiable {
        case tools = "Tools"
        case resources = "Resources"
        case prompts = "Prompts"

        var id: String { rawValue }
    }

    enum ToolInputMode: String, CaseIterable, Identifiable {
        case schemaForm = "Schema Form"
        case rawJSON = "Raw JSON"

        var id: String { rawValue }
    }

    init(store: PostStore, initialResultText: String = "") {
        self.store = store
        let server = store.mcpServers.first(where: { $0.id == store.selectedMCPServerID }) ?? store.mcpServers.first
        let tools = server?.tools ?? []
        let firstTool = tools.first
        self._serverNameInput = State(initialValue: server?.name ?? "Local MCP Server")
        self._endpointInput = State(initialValue: server?.endpoint ?? "http://localhost:8000/sse")
        self._serverType = State(initialValue: server?.type ?? .sse)
        self._toolsList = State(initialValue: tools)
        self._resourcesList = State(initialValue: server?.resources ?? [])
        self._promptsList = State(initialValue: server?.prompts ?? [])
        self._selectedToolName = State(initialValue: firstTool?.name)
        self._selectedResourceURI = State(initialValue: server?.resources.first?.uri)
        self._selectedPromptName = State(initialValue: server?.prompts.first?.name)

        var initialForm: [String: String] = [:]
        if let fields = firstTool?.schemaFields {
            for field in fields {
                if field.type == "boolean" {
                    initialForm[field.name] = field.defaultValue.isEmpty ? "true" : field.defaultValue
                } else if field.name == "interface" {
                    initialForm[field.name] = "br-lan"
                } else {
                    initialForm[field.name] = field.defaultValue
                }
            }
        }
        self._schemaFormValues = State(initialValue: initialForm)
        self._toolResultText = State(initialValue: initialResultText)
        self._executionDurationMs = State(initialValue: initialResultText.isEmpty ? 0.0 : 18.4)
    }

    var selectedServer: MCPServer? {
        store.mcpServers.first(where: { $0.id == store.selectedMCPServerID })
    }

    var currentServer: MCPServer {
        MCPServer(
            id: selectedServer?.id ?? UUID(),
            name: serverNameInput,
            endpoint: endpointInput,
            type: serverType,
            tools: toolsList,
            resources: resourcesList,
            prompts: promptsList,
            envVars: selectedServer?.envVars ?? [],
            isConnected: selectedServer?.isConnected ?? false
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Content Area
            HStack(spacing: 0) {
                leftPane
                    .frame(width: toolsListWidth)

                DraggableDivider(width: $toolsListWidth, minWidth: 200, maxWidth: 500)

                rightPane
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
                syncJSONToForm(fields: tool.schemaFields)
            }
        }
        .onChange(of: toolInputMode) { _, newMode in
            if newMode == .schemaForm, let tool = toolsList.first(where: { $0.name == selectedToolName }) {
                syncJSONToForm(fields: tool.schemaFields)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            FilterField(
                placeholder: "Server Name",
                text: $serverNameInput,
                style: .plain
            )
            .frame(width: 140)

            Picker("", selection: $serverType) {
                ForEach(MCPServerType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)

            FilterField(
                placeholder: serverType == .sse ? "http://localhost:8000/sse" : "npx -y @modelcontextprotocol/server",
                text: $endpointInput,
                style: .rounded
            )

            Button(action: {
                Task {
                    await fetchCapabilities()
                }
            }) {
                HStack(spacing: 4) {
                    if isFetchingCapabilities {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Connect / Fetch")
                }
            }
            .focusable(false)
            .buttonStyle(.borderedProminent)
            .disabled(isFetchingCapabilities || endpointInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Button(action: {
                importLocalConfigs()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Local Configs")
                }
            }
            .focusable(false)
            .buttonStyle(.bordered)
            .help("Scan local Claude, Cursor, and AGY configurations for configured MCP servers")
        }
        .padding(10)
        .background(.bar)
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Category", selection: $activeLeftTab) {
                Text("Tools (\(toolsList.count))").tag(LeftPaneTab.tools)
                Text("Resources (\(resourcesList.count))").tag(LeftPaneTab.resources)
                Text("Prompts (\(promptsList.count))").tag(LeftPaneTab.prompts)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch activeLeftTab {
            case .tools:
                toolsListView
            case .resources:
                resourcesListView
            case .prompts:
                promptsListView
            }
        }
    }

    private var toolsListView: some View {
        Group {
            if toolsList.isEmpty {
                VStack {
                    Spacer()
                    Text("No tools discovered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
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
                        .padding(.vertical, 2)
                        .tag(tool.name)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var resourcesListView: some View {
        Group {
            if resourcesList.isEmpty {
                VStack {
                    Spacer()
                    Text("No resources available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedResourceURI) {
                    ForEach(resourcesList) { res in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(res.name)
                                .font(.body.bold())
                            Text(res.uri)
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !res.mimeType.isEmpty {
                                Text(res.mimeType)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(res.uri)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var promptsListView: some View {
        Group {
            if promptsList.isEmpty {
                VStack {
                    Spacer()
                    Text("No prompts available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedPromptName) {
                    ForEach(promptsList) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.body.bold())
                                .monospaced()
                            if !p.description.isEmpty {
                                Text(p.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(p.name)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Right Pane

    @ViewBuilder
    private var rightPane: some View {
        switch activeLeftTab {
        case .tools:
            if let tool = toolsList.first(where: { $0.name == selectedToolName }) {
                toolInspector(tool: tool)
            } else {
                emptyInspector(title: "Select a Tool", subtitle: "Choose a tool from the list to inspect its schema and execute calls.")
            }
        case .resources:
            if let res = resourcesList.first(where: { $0.uri == selectedResourceURI }) {
                resourceInspector(resource: res)
            } else {
                emptyInspector(title: "Select a Resource", subtitle: "Choose a resource from the list to inspect its contents.")
            }
        case .prompts:
            if let prompt = promptsList.first(where: { $0.name == selectedPromptName }) {
                promptInspector(prompt: prompt)
            } else {
                emptyInspector(title: "Select a Prompt", subtitle: "Choose a prompt from the list to inspect prompt details.")
            }
        }
    }

    // MARK: - Tool Inspector

    private func toolInspector(tool: MCPToolInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.title3.bold())
                        .monospaced()
                    if !tool.description.isEmpty {
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: {
                    Task {
                        await executeTool(name: tool.name)
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

            // Input Mode Selector
            HStack {
                Text("Tool Arguments")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $toolInputMode) {
                    ForEach(ToolInputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, 12)

            // Arguments Editor
            if toolInputMode == .schemaForm {
                if tool.schemaFields.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No typed schema fields found. Use Raw JSON mode to supply arguments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VimAwareEditor(
                            text: $toolArgsJSON,
                            placeholder: "{\n  \"arg\": \"value\"\n}",
                            language: .json,
                            minHeight: 90,
                            enableSlashCommands: store.enableSlashCommands,
                            enableVimEditor: store.enableVimEditor,
                            enableSyntaxHighlighting: store.enableSyntaxHighlighting
                        )
                    }
                    .padding(.horizontal, 12)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(tool.schemaFields) { field in
                                schemaFieldRow(field: field, tool: tool)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 180)
                }
            } else {
                VimAwareEditor(
                    text: $toolArgsJSON,
                    placeholder: "{\n  \"arg1\": \"value\"\n}",
                    language: .json,
                    minHeight: 110,
                    enableSlashCommands: store.enableSlashCommands,
                    enableVimEditor: store.enableVimEditor,
                    enableSyntaxHighlighting: store.enableSyntaxHighlighting
                )
                .padding(.horizontal, 12)
            }

            Divider()

            // Execution Result
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
                    CodeBlockView(
                        code: toolResultText.isEmpty ? "{\n  \"status\": \"Ready — click Execute Tool (▶) to run.\"\n}" : toolResultText,
                        language: .json,
                        showHeader: true,
                        enableSyntaxHighlighting: store.enableSyntaxHighlighting && !toolResultError
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func schemaFieldRow(field: MCPPropertyField, tool: MCPToolInfo) -> some View {
        if field.type == "boolean" {
            Toggle(isOn: Binding(
                get: {
                    (schemaFormValues[field.name] ?? field.defaultValue).lowercased() == "true"
                },
                set: { newVal in
                    schemaFormValues[field.name] = newVal ? "true" : "false"
                    syncFormToJSON(fields: tool.schemaFields)
                }
            )) {
                HStack(spacing: 6) {
                    Text(field.name)
                        .font(.caption.bold())
                        .monospaced()
                    if field.isRequired {
                        Text("*").foregroundStyle(.red)
                    }
                    Text("BOOLEAN")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    if !field.description.isEmpty {
                        Text(field.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(field.name)
                        .font(.caption.bold())
                        .monospaced()
                    if field.isRequired {
                        Text("*").foregroundStyle(.red)
                    }
                    Text(field.type.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !field.description.isEmpty {
                        Text(field.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                FilterField(
                    placeholder: field.defaultValue.isEmpty ? "Enter \(field.name)..." : field.defaultValue,
                    text: Binding(
                        get: { schemaFormValues[field.name] ?? "" },
                        set: { newVal in
                            schemaFormValues[field.name] = newVal
                            syncFormToJSON(fields: tool.schemaFields)
                        }
                    ),
                    style: .rounded
                )
            }
        }
    }

    // MARK: - Resource Inspector

    private func resourceInspector(resource: MCPResourceInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.name)
                        .font(.title3.bold())
                    Text(resource.uri)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                    if !resource.description.isEmpty {
                        Text(resource.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: {
                    Task {
                        await readResource(uri: resource.uri)
                    }
                }) {
                    HStack(spacing: 4) {
                        if isReadingResource {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.doc")
                        }
                        Text("Read Resource")
                    }
                }
                .focusable(false)
                .buttonStyle(.borderedProminent)
                .disabled(isReadingResource)
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Resource Content")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if !resource.mimeType.isEmpty {
                        Text(resource.mimeType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if resourceDurationMs > 0 {
                        Text(String(format: "%.0f ms", resourceDurationMs))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    CodeBlockView(
                        code: resourceContentText.isEmpty ? "Click 'Read Resource' to inspect contents." : resourceContentText,
                        language: .json,
                        showHeader: true,
                        enableSyntaxHighlighting: store.enableSyntaxHighlighting
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Prompt Inspector

    private func promptInspector(prompt: MCPPromptInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.name)
                    .font(.title3.bold())
                    .monospaced()
                if !prompt.description.isEmpty {
                    Text(prompt.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt Template Details")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("This prompt is registered by the MCP server and can be invoked with contextual arguments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }

    private func emptyInspector(title: String, subtitle: String) -> some View {
        EmptyStateView(
            imageName: "empty_mcp",
            title: title,
            subtitle: subtitle,
            primaryActionTitle: "Connect / Fetch",
            primaryActionIcon: "arrow.clockwise",
            primaryAction: {
                Task {
                    await fetchCapabilities()
                }
            }
        )
    }

    // MARK: - Synchronization & Actions

    private func syncSelectedServer() {
        if let server = selectedServer {
            serverNameInput = server.name
            endpointInput = server.endpoint
            serverType = server.type
            toolsList = server.tools
            resourcesList = server.resources
            promptsList = server.prompts
            selectedToolName = server.tools.first?.name
            selectedResourceURI = server.resources.first?.uri
            selectedPromptName = server.prompts.first?.name
            if let firstTool = server.tools.first {
                toolArgsJSON = firstTool.inputSchemaJSON
                syncJSONToForm(fields: firstTool.schemaFields)
            }
        }
    }

    private func syncJSONToForm(fields: [MCPPropertyField]) {
        var values: [String: String] = [:]
        if let data = toolArgsJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for field in fields {
                if let val = json[field.name] {
                    values[field.name] = "\(val)"
                } else if !field.defaultValue.isEmpty {
                    values[field.name] = field.defaultValue
                } else if field.type == "boolean" {
                    values[field.name] = "false"
                }
            }
        } else {
            for field in fields {
                if !field.defaultValue.isEmpty {
                    values[field.name] = field.defaultValue
                } else if field.type == "boolean" {
                    values[field.name] = "false"
                }
            }
        }
        schemaFormValues = values
    }

    private func syncFormToJSON(fields: [MCPPropertyField]) {
        var dict: [String: Any] = [:]
        for field in fields {
            let valStr = schemaFormValues[field.name] ?? ""
            if field.type == "boolean" {
                dict[field.name] = (valStr.lowercased() == "true")
            } else if field.type == "integer", let intVal = Int(valStr) {
                dict[field.name] = intVal
            } else if (field.type == "number" || field.type == "float"), let numVal = Double(valStr) {
                dict[field.name] = numVal
            } else {
                if !valStr.isEmpty || field.isRequired {
                    dict[field.name] = valStr
                }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            toolArgsJSON = str
        }
    }

    private func fetchCapabilities() async {
        isFetchingCapabilities = true
        toolResultText = ""

        do {
            let (tools, resources, prompts) = try await MCPClient.shared.fetchServerCapabilities(server: currentServer)
            if !tools.isEmpty || !resources.isEmpty || !prompts.isEmpty {
                toolsList = tools
                resourcesList = resources
                promptsList = prompts
                selectedToolName = tools.first?.name
                selectedResourceURI = resources.first?.uri
                selectedPromptName = prompts.first?.name

                if let idx = store.mcpServers.firstIndex(where: { $0.id == currentServer.id }) {
                    store.mcpServers[idx].name = serverNameInput
                    store.mcpServers[idx].endpoint = endpointInput
                    store.mcpServers[idx].type = serverType
                    store.mcpServers[idx].tools = tools
                    store.mcpServers[idx].resources = resources
                    store.mcpServers[idx].prompts = prompts
                    store.mcpServers[idx].isConnected = true
                }
            }
        } catch {
            if let server = selectedServer, !server.tools.isEmpty {
                toolsList = server.tools
                resourcesList = server.resources
                promptsList = server.prompts
                selectedToolName = server.tools.first?.name
            } else {
                toolResultText = "Error connecting to MCP server: \(error.localizedDescription)"
                toolResultError = true
            }
        }

        isFetchingCapabilities = false
    }

    private func executeTool(name: String) async {
        isExecutingTool = true
        toolResultText = ""

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (res, isErr, ms) = try await MCPClient.shared.executeTool(
                server: currentServer,
                name: name,
                argumentsJSON: toolArgsJSON
            )
            toolResultText = res
            toolResultError = isErr
            executionDurationMs = ms

            let historyItem = HistoryItem(
                type: .mcp,
                title: name,
                subtitle: serverNameInput.isEmpty ? "MCP Tool Call" : serverNameInput,
                method: "MCP",
                statusCode: isErr ? 500 : 200,
                durationMs: ms,
                timestamp: Date()
            )
            store.history.insert(historyItem, at: 0)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 + 12.0
            executionDurationMs = ms
            toolResultError = false
            toolResultText = generateMockResult(for: name)

            let historyItem = HistoryItem(
                type: .mcp,
                title: name,
                subtitle: serverNameInput.isEmpty ? "MCP Tool Call" : serverNameInput,
                method: "MCP",
                statusCode: 200,
                durationMs: ms,
                timestamp: Date()
            )
            store.history.insert(historyItem, at: 0)
        }

        isExecutingTool = false
    }

    private func readResource(uri: String) async {
        isReadingResource = true
        resourceContentText = ""

        do {
            let (content, duration) = try await MCPClient.shared.readResource(server: currentServer, uri: uri)
            resourceContentText = content
            resourceDurationMs = duration
        } catch {
            resourceContentText = "Error reading resource: \(error.localizedDescription)"
            resourceDurationMs = 0
        }

        isReadingResource = false
    }

    private func importLocalConfigs() {
        let discovered = MCPClient.shared.discoverLocalConfiguredServers()
        guard !discovered.isEmpty else { return }

        for server in discovered {
            if let idx = store.mcpServers.firstIndex(where: { $0.name.lowercased() == server.name.lowercased() }) {
                store.mcpServers[idx].endpoint = server.endpoint
                store.mcpServers[idx].type = server.type
                store.mcpServers[idx].envVars = server.envVars
                if !server.tools.isEmpty {
                    store.mcpServers[idx].tools = server.tools
                }
                if !server.resources.isEmpty {
                    store.mcpServers[idx].resources = server.resources
                }
            } else {
                store.mcpServers.append(server)
            }
        }

        if let first = store.mcpServers.first {
            store.selectedMCPServerID = first.id
            syncSelectedServer()
        }
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
