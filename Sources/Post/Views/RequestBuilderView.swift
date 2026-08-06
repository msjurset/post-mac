import SwiftUI

struct RequestBuilderView: View {
    @ObservedObject var store: PostStore
    @Binding var request: HTTPRequest
    @State private var selectedEditorTab: EditorTab = .params
    @State private var showingCopiedToast: Bool = false

    enum EditorTab: String, CaseIterable, Identifiable {
        case params = "Params"
        case headers = "Headers"
        case body = "Body"

        var id: String { rawValue }
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

                    Button(action: {
                        let curlStr = HTTPClient.shared.exportToCURL(request: request)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curlStr, forType: .string)
                        showingCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showingCopiedToast = false
                        }
                    }) {
                        Label(showingCopiedToast ? "Copied!" : "Copy cURL", systemImage: showingCopiedToast ? "checkmark" : "doc.on.doc")
                    }
                    .focusable(false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

            // Request Configuration Tabs (Params, Headers, Body)
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedEditorTab) {
                    ForEach(EditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                switch selectedEditorTab {
                case .params:
                    keyValueEditorView(items: $request.queryParams, keyPlaceholder: "Query Param", valuePlaceholder: "Value")
                case .headers:
                    keyValueEditorView(items: $request.headers, keyPlaceholder: "Header Name", valuePlaceholder: "Header Value")
                case .body:
                    bodyEditorView
                }
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

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if request.bodyType != .none {
                FilterField(
                    placeholder: request.bodyType == .json ? "{\n  \"key\": \"value\"\n}" : "Enter request payload body text...",
                    text: $request.bodyText,
                    multiline: true,
                    alignment: .left
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
