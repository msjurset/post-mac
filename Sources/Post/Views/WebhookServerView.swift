import SwiftUI

public enum WebhookViewMode: String, CaseIterable, Identifiable {
    case payloads = "Captured Payloads"
    case mockRules = "Mock & Forwarding Rules"

    public var id: String { rawValue }
}

struct WebhookServerView: View {
    @ObservedObject var store: PostStore
    @ObservedObject var server: WebhookServer
    @State private var viewMode: WebhookViewMode = .payloads
    @State private var selectedPayloadID: UUID?
    @State private var selectedRuleID: UUID?
    @State private var payloadsListWidth: CGFloat = 280
    @State private var rulesListWidth: CGFloat = 280

    // Captured payload actions
    @State private var replayTargetURL: String = "http://localhost:8080/webhook"
    @State private var isReplaying: Bool = false
    @State private var showReplayBadge: Bool = false
    @State private var showCopyCurlBadge: Bool = false

    init(store: PostStore, initialMode: WebhookViewMode = .payloads) {
        self.store = store
        self.server = store.webhookServer
        self._viewMode = State(initialValue: initialMode)
        self._selectedPayloadID = State(initialValue: store.webhookServer.payloads.first?.id)
        self._selectedRuleID = State(initialValue: store.webhookServer.mockRules.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            modeTabBar
            Divider()

            Group {
                switch viewMode {
                case .payloads:
                    capturedPayloadsSplitView
                case .mockRules:
                    mockRulesSplitView
                }
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            Label("Local Webhook Server", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            Spacer()

            HStack(spacing: 6) {
                Text("Port:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FilterField(
                    placeholder: "9090",
                    text: Binding(
                        get: { String(store.webhookServer.port) },
                        set: { if let p = UInt16($0) { store.webhookServer.port = p } }
                    ),
                    isDisabled: store.webhookServer.isRunning,
                    style: .rounded
                )
                .frame(width: 70)
            }

            if store.webhookServer.isRunning {
                Button(action: { store.webhookServer.stop() }) {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .focusable(false)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { store.webhookServer.start() }) {
                    Label("Start Listener", systemImage: "play.fill")
                }
                .focusable(false)
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }

            if viewMode == .payloads {
                Button(action: {
                    store.webhookServer.clearPayloads()
                    selectedPayloadID = nil
                }) {
                    Image(systemName: "trash")
                }
                .focusable(false)
                .buttonStyle(.bordered)
                .help("Clear All Captured Payloads")
            }
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Mode Tab Bar
    private var modeTabBar: some View {
        HStack {
            Picker("View Mode", selection: $viewMode) {
                ForEach(WebhookViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)

            Spacer()

            if viewMode == .mockRules {
                Button(action: {
                    let newRule = WebhookMockRule(
                        name: "New Mock Rule",
                        pathPrefix: "/webhook/new",
                        statusCode: 200,
                        responseHeaders: [KeyValueItem(key: "Content-Type", value: "application/json")],
                        responseBody: "{\"status\":\"ok\"}",
                        delayMs: 0,
                        forwardToURL: "",
                        isEnabled: true
                    )
                    server.addRule(newRule)
                    selectedRuleID = newRule.id
                }) {
                    Label("Add Rule", systemImage: "plus")
                }
                .focusable(false)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    // MARK: - Captured Payloads Mode Split View
    private var capturedPayloadsSplitView: some View {
        HStack(spacing: 0) {
            // Left: List of Payloads
            List(selection: $selectedPayloadID) {
                ForEach(server.payloads) { payload in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(payload.method)
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                            Text(payload.path)
                                .font(.caption.bold())
                                .monospaced()
                                .lineLimit(1)
                            Spacer()
                            StatusCodeBadge(code: payload.responseStatusCode)
                        }
                        HStack {
                            Text(payload.clientIP)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(payload.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let fwd = payload.forwardedTo, !fwd.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.turn.up.right")
                                    .font(.caption2)
                                Text(fwd)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(payload.id)
                }
            }
            .frame(width: payloadsListWidth)
            .listStyle(.inset)

            DraggableDivider(width: $payloadsListWidth, minWidth: 180, maxWidth: 500)

            // Right: Payload Inspector
            if let payload = server.payloads.first(where: { $0.id == selectedPayloadID }) {
                payloadInspectorView(payload: payload)
            } else {
                EmptyStateView(
                    imageName: "empty_webhooks",
                    title: "Local Webhook Listener",
                    subtitle: server.isRunning
                        ? "Listening for webhooks on port \(String(server.port))...\nSend HTTP POST or GET requests to http://localhost:\(String(server.port))/webhook"
                        : "Start the local network server on port \(String(server.port)) to capture and inspect incoming webhooks in real time.",
                    primaryActionTitle: server.isRunning ? "Stop Server" : "Start Listener",
                    primaryActionIcon: server.isRunning ? "stop.fill" : "play.fill",
                    primaryAction: {
                        if server.isRunning {
                            server.stop()
                        } else {
                            server.start()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Payload Inspector View
    private func payloadInspectorView(payload: WebhookPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header details
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(payload.method)
                                .font(.title3.bold())
                                .foregroundStyle(.green)
                            Text(payload.path)
                                .font(.title3.bold())
                                .monospaced()
                            StatusCodeBadge(code: payload.responseStatusCode)
                        }
                        Text("Received from \(payload.clientIP) at \(payload.timestamp.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Action Bar: Replay, Open in Workbench, Copy cURL
                VStack(alignment: .leading, spacing: 10) {
                    Text("Webhook Actions")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Text("Replay URL:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FilterField(
                            placeholder: "http://localhost:8080/webhook",
                            text: $replayTargetURL,
                            style: .rounded
                        )
                        .frame(maxWidth: 280)

                        Button(action: {
                            Task {
                                isReplaying = true
                                await store.replayWebhook(payload, to: replayTargetURL)
                                isReplaying = false
                                showReplayBadge = true
                                try? await Task.sleep(for: .seconds(2))
                                showReplayBadge = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isReplaying {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Replay Now")
                            }
                        }
                        .focusable(false)
                        .buttonStyle(.borderedProminent)
                        .disabled(replayTargetURL.trimmingCharacters(in: .whitespaces).isEmpty || isReplaying)

                        if showReplayBadge {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Replayed")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            .transition(.opacity)
                        }

                        Spacer()

                        Button(action: {
                            store.convertWebhookToRequest(payload)
                        }) {
                            Label("Open in Workbench", systemImage: "arrow.up.right.square")
                        }
                        .focusable(false)
                        .buttonStyle(.bordered)
                        .help("Convert captured webhook into an editable request in HTTP Workbench")

                        Button(action: {
                            let curl = payload.asCURL(port: server.port)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(curl, forType: .string)
                            showCopyCurlBadge = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showCopyCurlBadge = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopyCurlBadge ? "checkmark" : "doc.on.doc")
                                Text(showCopyCurlBadge ? "Copied" : "Copy cURL")
                            }
                        }
                        .focusable(false)
                        .buttonStyle(.bordered)
                        .help("Copy captured webhook as a runnable curl command")
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                if let fwd = payload.forwardedTo, !fwd.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.up.right")
                            .foregroundStyle(.blue)
                        Text("Auto-forwarded to:")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(fwd)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 4)
                }

                Divider()

                // Headers
                VStack(alignment: .leading, spacing: 6) {
                    Text("Headers (\(payload.headers.count))")
                        .font(.headline)
                    ForEach(payload.headers) { h in
                        HStack(alignment: .top) {
                            Text(h.key)
                                .font(.caption.bold())
                                .monospaced()
                                .frame(width: 140, alignment: .leading)
                            Text(h.value)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Divider()

                // Body Payload
                VStack(alignment: .leading, spacing: 6) {
                    Text("Body Payload")
                        .font(.headline)
                    CodeBlockView(
                        code: payload.formattedBody.isEmpty ? "(Empty Body)" : payload.formattedBody,
                        language: .json,
                        showHeader: true,
                        enableSyntaxHighlighting: store.enableSyntaxHighlighting
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Mock & Forwarding Rules Mode Split View
    private var mockRulesSplitView: some View {
        HStack(spacing: 0) {
            // Left: Rules List
            List(selection: $selectedRuleID) {
                ForEach($server.mockRules) { $rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(rule.name.isEmpty ? "Unnamed Rule" : rule.name)
                                    .font(.body.bold())
                                    .lineLimit(1)
                                Spacer()
                                StatusCodeBadge(code: rule.statusCode)
                            }
                            Text(rule.pathPrefix)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if !rule.forwardToURL.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.turn.up.right")
                                        .font(.caption2)
                                    Text(rule.forwardToURL)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(rule.id)
                    .contextMenu {
                        Button("Delete Rule", role: .destructive) {
                            server.removeRule(id: rule.id)
                            if selectedRuleID == rule.id {
                                selectedRuleID = server.mockRules.first?.id
                            }
                        }
                    }
                }
            }
            .frame(width: rulesListWidth)
            .listStyle(.inset)

            DraggableDivider(width: $rulesListWidth, minWidth: 180, maxWidth: 500)

            // Right: Selected Rule Editor
            if let index = server.mockRules.firstIndex(where: { $0.id == selectedRuleID }) {
                ruleEditorView(ruleBinding: $server.mockRules[index])
            } else {
                EmptyStateView(
                    imageName: "empty_webhooks",
                    title: "Mock & Forwarding Rules",
                    subtitle: "Configure custom HTTP status codes, artificial delays, response bodies, and auto-forwarding endpoints for incoming webhooks.",
                    primaryActionTitle: "Add Mock Rule",
                    primaryActionIcon: "plus",
                    primaryAction: {
                        let newRule = WebhookMockRule(
                            name: "New Mock Rule",
                            pathPrefix: "/webhook/custom",
                            statusCode: 200,
                            responseHeaders: [KeyValueItem(key: "Content-Type", value: "application/json")],
                            responseBody: "{\"status\":\"ok\"}",
                            delayMs: 0,
                            forwardToURL: "",
                            isEnabled: true
                        )
                        server.addRule(newRule)
                        selectedRuleID = newRule.id
                    }
                )
            }
        }
    }

    // MARK: - Rule Editor View
    private func ruleEditorView(ruleBinding: Binding<WebhookMockRule>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top control bar
                HStack {
                    Toggle("Enable Rule", isOn: ruleBinding.isEnabled)
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        let idToDelete = ruleBinding.wrappedValue.id
                        server.removeRule(id: idToDelete)
                        if selectedRuleID == idToDelete {
                            selectedRuleID = server.mockRules.first?.id
                        }
                    }) {
                        Label("Delete Rule", systemImage: "trash")
                    }
                    .focusable(false)
                    .buttonStyle(.bordered)
                }

                Divider()

                // Rule Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rule Name")
                        .font(.subheadline.bold())
                    FilterField(
                        placeholder: "e.g. Rate Limit Simulation",
                        text: ruleBinding.name,
                        style: .rounded
                    )
                }

                // Path Prefix
                VStack(alignment: .leading, spacing: 6) {
                    Text("Path Prefix")
                        .font(.subheadline.bold())
                    FilterField(
                        placeholder: "/webhook",
                        text: ruleBinding.pathPrefix,
                        style: .rounded
                    )
                    Text("Incoming webhooks matching this path prefix will trigger this rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Status Code
                VStack(alignment: .leading, spacing: 6) {
                    Text("Response Status Code")
                        .font(.subheadline.bold())

                    HStack(spacing: 12) {
                        Picker("Status Code", selection: ruleBinding.statusCode) {
                            Text("200 OK").tag(200)
                            Text("201 Created").tag(201)
                            Text("400 Bad Request").tag(400)
                            Text("401 Unauthorized").tag(401)
                            Text("429 Too Many Requests").tag(429)
                            Text("500 Internal Server Error").tag(500)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)

                        Text("Custom:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FilterField(
                            placeholder: "200",
                            text: Binding(
                                get: { String(ruleBinding.wrappedValue.statusCode) },
                                set: { if let c = Int($0) { ruleBinding.wrappedValue.statusCode = c } }
                            ),
                            style: .rounded
                        )
                        .frame(width: 70)
                    }
                }

                // Artificial Delay
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artificial Delay (ms)")
                        .font(.subheadline.bold())

                    HStack(spacing: 8) {
                        FilterField(
                            placeholder: "0",
                            text: Binding(
                                get: { String(ruleBinding.wrappedValue.delayMs) },
                                set: {
                                    if let ms = Int($0) {
                                        ruleBinding.wrappedValue.delayMs = ms
                                    } else if $0.isEmpty {
                                        ruleBinding.wrappedValue.delayMs = 0
                                    }
                                }
                            ),
                            style: .rounded
                        )
                        .frame(width: 100)

                        Text("ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Simulate network latency or rate-limiting delays before responding to caller.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Auto-Forwarding Target URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-Forward Target URL (Optional)")
                        .font(.subheadline.bold())

                    FilterField(
                        placeholder: "http://localhost:8080/target-endpoint",
                        text: ruleBinding.forwardToURL,
                        style: .rounded
                    )
                    Text("When set, all incoming webhooks matching this rule are asynchronously forwarded to this URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Response Body
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Mock Response Body (JSON)")
                            .font(.subheadline.bold())
                        if store.enableSlashCommands {
                            Text("Type / for slash commands")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        // Presets
                        HStack(spacing: 6) {
                            Text("Presets:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Button("{\"status\":\"ok\"}") {
                                ruleBinding.wrappedValue.responseBody = "{\n  \"status\": \"ok\"\n}"
                            }
                            .focusable(false)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button("{\"error\":\"rate_limit\"}") {
                                ruleBinding.wrappedValue.responseBody = "{\n  \"error\": \"Too Many Requests\",\n  \"retry_after\": 60\n}"
                            }
                            .focusable(false)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }

                    VimAwareEditor(
                        text: ruleBinding.responseBody,
                        placeholder: "{\n  \"status\": \"ok\"\n}",
                        language: .json,
                        minHeight: 130,
                        enableSlashCommands: store.enableSlashCommands,
                        enableVimEditor: store.enableVimEditor,
                        enableSyntaxHighlighting: store.enableSyntaxHighlighting
                    )
                }
            }
            .padding(16)
        }
    }
}
