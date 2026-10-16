import SwiftUI

struct RequestBuilderView: View {
    @ObservedObject var store: PostStore
    @Binding var request: HTTPRequest
    @State private var selectedEditorTab: EditorTab = .params
    @State private var showingCopiedToast: Bool = false

    enum EditorTab: String, CaseIterable, Identifiable {
        case params = "Params"
        case auth = "Auth"
        case headers = "Headers"
        case body = "Body"
        case chaining = "Chaining"

        var id: String { rawValue }
    }

    init(store: PostStore, request: Binding<HTTPRequest>, initialTab: EditorTab = .params) {
        self.store = store
        self._request = request
        self._selectedEditorTab = State(initialValue: initialTab)
    }

    private var selectedEnvironmentName: String {
        if let id = store.selectedEnvironmentID,
           let env = store.environments.first(where: { $0.id == id }) {
            return env.name
        }
        return "No Environment"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Request Header Bar (Name, Method, URL, Send)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    FilterField(
                        placeholder: "Request Name",
                        text: $request.name,
                        style: .plain
                    )
                    .font(.headline)

                    Spacer()

                    // Environment Picker Menu & Gear Button
                    HStack(spacing: 4) {
                        Menu {
                            Button(action: {
                                store.selectedEnvironmentID = nil
                            }) {
                                HStack {
                                    Text("No Environment (Global)")
                                    if store.selectedEnvironmentID == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            if !store.environments.isEmpty {
                                Divider()
                                ForEach(store.environments) { env in
                                    Button(action: {
                                        store.selectedEnvironmentID = env.id
                                    }) {
                                        HStack {
                                            Text(env.name)
                                            if store.selectedEnvironmentID == env.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(selectedEnvironmentName, systemImage: "globe")
                        }
                        .controlSize(.small)
                        .fixedSize()

                        Button(action: {
                            store.showingEnvironmentSheet = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                        .focusable(false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Manage Environments")
                    }

                    // Code Snippet Export (native split button: 1-click Copy cURL + dropdown for Go/Swift/Python)
                    Menu {
                        ForEach(CodeExportFormat.allCases) { fmt in
                            Button("Copy \(fmt.rawValue)") {
                                copyCodeSnippet(format: fmt)
                            }
                        }
                    } label: {
                        Label(
                            showingCopiedToast ? "Copied!" : "Copy cURL",
                            systemImage: showingCopiedToast ? "checkmark" : "doc.on.doc"
                        )
                    } primaryAction: {
                        copyCodeSnippet(format: .curl)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    Picker("Method", selection: $request.method) {
                        ForEach(HTTPMethod.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)

                    FilterField(
                        placeholder: "https://api.example.com/endpoint",
                        text: $request.url,
                        onCommit: {
                            Task {
                                await store.executeSelectedRequest()
                            }
                        },
                        style: .rounded
                    )

                    Button(action: {
                        Task {
                            await store.executeSelectedRequest()
                        }
                    }) {
                        HStack {
                            if store.isExecuting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send")
                        }
                    }
                    .focusable(false)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isExecuting || request.url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .background(.bar)

            Divider()

            // Request Configuration Tabs (Params, Auth, Headers, Body, Chaining)
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedEditorTab) {
                    ForEach(EditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                switch selectedEditorTab {
                case .params:
                    keyValueEditorView(items: $request.queryParams, keyPlaceholder: "Query Param", valuePlaceholder: "Value")
                case .auth:
                    authEditorView
                case .headers:
                    keyValueEditorView(items: $request.headers, keyPlaceholder: "Header Name", valuePlaceholder: "Header Value")
                case .body:
                    bodyEditorView
                case .chaining:
                    chainingEditorView
                }
            }
        }
    }

    private func copyCodeSnippet(format: CodeExportFormat) {
        let snippet = CodeGenerator.generate(for: request, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        showingCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showingCopiedToast = false
        }
    }

    private var authEditorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Auth Type:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Auth Type", selection: $request.auth.type) {
                        Text("None").tag(AuthType.none)
                        Text("Bearer Token").tag(AuthType.bearer)
                        Text("Basic Auth").tag(AuthType.basic)
                        Text("API Key").tag(AuthType.apiKey)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)

                    Spacer()
                }

                Divider()

                switch request.auth.type {
                case .none:
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "lock.open")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No Authorization")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("This request does not include authorization credentials or headers.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)

                case .bearer:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bearer Token")
                            .font(.subheadline.bold())
                        FilterField(
                            placeholder: "Enter token or {{bearer_token}}",
                            text: $request.auth.bearerToken,
                            style: .rounded
                        )
                        Text("Appends header: Authorization: Bearer <token>")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .basic:
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(.subheadline.bold())
                            FilterField(
                                placeholder: "Username or {{username}}",
                                text: $request.auth.basicUsername,
                                style: .rounded
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.subheadline.bold())
                            FilterField(
                                placeholder: "Password or {{password}}",
                                text: $request.auth.basicPassword,
                                style: .rounded
                            )
                        }
                        Text("Appends header: Authorization: Basic <base64(username:password)>")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .apiKey:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Key Name")
                                    .font(.subheadline.bold())
                                FilterField(
                                    placeholder: "e.g. X-API-Key or api_key",
                                    text: $request.auth.apiKeyName,
                                    style: .rounded
                                )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Value")
                                    .font(.subheadline.bold())
                                FilterField(
                                    placeholder: "Value or {{api_key}}",
                                    text: $request.auth.apiKeyValue,
                                    style: .rounded
                                )
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Add to:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Picker("Location", selection: $request.auth.apiKeyLocation) {
                                Text("Header").tag(APIKeyLocation.header)
                                Text("Query Params").tag(APIKeyLocation.query)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)

                            Spacer()
                        }

                        Text(request.auth.apiKeyLocation == .header
                            ? "Appends header: \(request.auth.apiKeyName.isEmpty ? "<Key>" : request.auth.apiKeyName): <Value>"
                            : "Appends URL query parameter: ?\(request.auth.apiKeyName.isEmpty ? "<Key>" : request.auth.apiKeyName)=<Value>")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private var chainingEditorView: some View {
        VStack(spacing: 0) {
            if request.extractions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Extraction Rules")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Extract values from this request's response JSON body and store them in environment variables for subsequent requests.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)

                    Button(action: {
                        request.extractions.append(
                            ResponseExtractionRule(id: UUID(), jsonPath: "$.token", targetVariable: "auth_token", isEnabled: true)
                        )
                    }) {
                        Label("Add Extraction Rule", systemImage: "plus")
                    }
                    .focusable(false)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(request.extractions.indices, id: \.self) { idx in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $request.extractions[idx].isEnabled)
                                .labelsHidden()

                            FilterField(
                                placeholder: "JSONPath (e.g. $.token or .id)",
                                text: $request.extractions[idx].jsonPath,
                                style: .plain
                            )
                            .frame(maxWidth: .infinity)

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            FilterField(
                                placeholder: "Variable (e.g. authToken)",
                                text: $request.extractions[idx].targetVariable,
                                style: .plain
                            )
                            .frame(maxWidth: .infinity)

                            Button(action: {
                                request.extractions.remove(at: idx)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .focusable(false)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Button(action: {
                        request.extractions.append(
                            ResponseExtractionRule(id: UUID(), jsonPath: "", targetVariable: "", isEnabled: true)
                        )
                    }) {
                        Label("Add Extraction Rule", systemImage: "plus")
                    }
                    .focusable(false)
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }
        }
    }

    private func keyValueEditorView(items: Binding<[KeyValueItem]>, keyPlaceholder: String, valuePlaceholder: String) -> some View {
        VStack(spacing: 0) {
            List {
                ForEach(items.wrappedValue.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        Toggle("", isOn: items[idx].isEnabled)
                            .labelsHidden()

                        FilterField(
                            placeholder: keyPlaceholder,
                            text: items[idx].key,
                            style: .plain
                        )
                        .frame(maxWidth: .infinity)

                        Text(":")
                            .foregroundStyle(.tertiary)

                        FilterField(
                            placeholder: valuePlaceholder,
                            text: items[idx].value,
                            style: .plain
                        )
                        .frame(maxWidth: .infinity)

                        Button(action: {
                            items.wrappedValue.remove(at: idx)
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .focusable(false)
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button(action: {
                    items.wrappedValue.append(KeyValueItem(key: "", value: "", isEnabled: true))
                }) {
                    Label("Add Row", systemImage: "plus")
                }
                .focusable(false)
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }

    private var bodyEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Body Type:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Body Type", selection: $request.bodyType) {
                    ForEach(BodyType.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                if store.enableSlashCommands && request.bodyType != .none {
                    Text("Type / for slash commands")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if request.bodyType == .json && !request.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        if let data = request.bodyText.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data),
                           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                           let str = String(data: pretty, encoding: .utf8) {
                            request.bodyText = str
                        }
                    }) {
                        Label("Format JSON", systemImage: "curlybraces")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if request.bodyType != .none {
                VimAwareEditor(
                    text: $request.bodyText,
                    placeholder: request.bodyType == .json ? "{\n  \"key\": \"value\"\n}" : (request.bodyType == .formData ? "param1=value1&param2=value2" : "Enter request payload body text..."),
                    language: request.bodyType == .json ? .json : .raw,
                    minHeight: 96,
                    enableSlashCommands: store.enableSlashCommands,
                    enableVimEditor: store.enableVimEditor,
                    enableSyntaxHighlighting: store.enableSyntaxHighlighting
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else {
                VStack {
                    Spacer()
                    Text("No body payload for this request.")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
