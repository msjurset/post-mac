import SwiftUI

struct ResponseView: View {
    let response: HTTPResponse?
    let previousResponses: [HTTPResponse]
    let enableSyntaxHighlighting: Bool
    @State private var selectedResponseTab: ResponseTab = .body
    @State private var jsonPathQuery: String = ""
    @State private var selectedBaselineID: UUID?
    @State private var showingCopiedJSONPath: Bool = false

    enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "Response Body"
        case headers = "Headers"
        case diff = "Diff"

        var id: String { rawValue }
    }

    init(
        response: HTTPResponse?,
        previousResponses: [HTTPResponse] = [],
        initialTab: ResponseTab = .body,
        initialJSONPath: String = "",
        enableSyntaxHighlighting: Bool = true
    ) {
        self.response = response
        self.previousResponses = previousResponses
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
        self._selectedResponseTab = State(initialValue: initialTab)
        self._jsonPathQuery = State(initialValue: initialJSONPath)
    }

    private var eligibleBaselineResponses: [HTTPResponse] {
        guard let current = response else { return previousResponses }
        return previousResponses.filter { $0.id != current.id }
    }

    private var baselineResponse: HTTPResponse? {
        if let id = selectedBaselineID, let found = eligibleBaselineResponses.first(where: { $0.id == id }) {
            return found
        }
        return eligibleBaselineResponses.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let response = response {
                // Response Metadata Header
                HStack(spacing: 12) {
                    StatusCodeBadge(code: response.statusCode, text: response.statusText)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(String(format: "%.0f ms", response.responseTimeMs))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text(formatByteSize(response.responseSizeBytes))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Picker("Tab", selection: $selectedResponseTab) {
                        ForEach(ResponseTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .padding(10)
                .background(.bar)

                Divider()

                switch selectedResponseTab {
                case .body:
                    responseBodyView(response: response)
                case .headers:
                    responseHeadersView(headers: response.headers)
                case .diff:
                    responseDiffView(currentResponse: response)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "paperplane")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No response data yet.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Hit 'Send' to fire the HTTP request and inspect results.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func responseBodyView(response: HTTPResponse) -> some View {
        VStack(spacing: 0) {
            // JSONPath Filter Bar
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)

                FilterField(
                    placeholder: "Filter JSONPath (e.g. $.data.items[0] or .id)...",
                    text: $jsonPathQuery,
                    style: .plain
                )

                if !jsonPathQuery.isEmpty {
                    Button(action: {
                        jsonPathQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .focusable(false)
                    .buttonStyle(.plain)

                    if let evaluated = JSONPathEvaluator.evaluate(jsonString: response.bodyText, path: jsonPathQuery) {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(evaluated, forType: .string)
                            showingCopiedJSONPath = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showingCopiedJSONPath = false
                            }
                        }) {
                            Label(showingCopiedJSONPath ? "Copied" : "Copy Result", systemImage: showingCopiedJSONPath ? "checkmark" : "doc.on.doc")
                        }
                        .focusable(false)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            if jsonPathQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView {
                    CodeBlockView(
                        code: response.formattedBody,
                        language: .json,
                        showHeader: true,
                        enableSyntaxHighlighting: enableSyntaxHighlighting
                    )
                    .padding(12)
                }
            } else {
                ScrollView {
                    let result = JSONPathEvaluator.evaluate(jsonString: response.bodyText, path: jsonPathQuery)
                    CodeBlockView(
                        code: result ?? "No matching JSON path",
                        language: .json,
                        showHeader: true,
                        enableSyntaxHighlighting: enableSyntaxHighlighting && result != nil
                    )
                    .padding(12)
                }
            }
        }
    }

    private func responseHeadersView(headers: [KeyValueItem]) -> some View {
        List(headers) { h in
            HStack {
                Text(h.key)
                    .font(.caption.bold())
                    .monospaced()
                    .frame(width: 180, alignment: .leading)
                Text(h.value)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
        }
        .listStyle(.inset)
    }

    private func responseDiffView(currentResponse: HTTPResponse) -> some View {
        VStack(spacing: 0) {
            if eligibleBaselineResponses.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No Previous Responses Available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Execute this request multiple times to compare changes in the response payload.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    Text("Baseline:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Baseline", selection: Binding(
                        get: { baselineResponse?.id },
                        set: { selectedBaselineID = $0 }
                    )) {
                        ForEach(eligibleBaselineResponses) { prev in
                            Text("\(prev.statusCode) \(prev.statusText) - \(formatDate(prev.timestamp)) (\(formatByteSize(prev.responseSizeBytes)))")
                                .tag(Optional(prev.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)

                    Spacer()

                    if let baseline = baselineResponse {
                        let lines = ResponseDiffEngine.diff(old: baseline.formattedBody, new: currentResponse.formattedBody)
                        let added = lines.filter { $0.kind == .added }.count
                        let removed = lines.filter { $0.kind == .removed }.count

                        HStack(spacing: 6) {
                            if added > 0 {
                                Text("+\(added)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            if removed > 0 {
                                Text("-\(removed)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                            if added == 0 && removed == 0 {
                                Text("Identical")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

                Divider()

                if let baseline = baselineResponse {
                    let diffLines = ResponseDiffEngine.diff(old: baseline.formattedBody, new: currentResponse.formattedBody)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diffLines) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(line.lineNumber != nil ? "\(line.lineNumber!)" : "")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 34, alignment: .trailing)

                                    Text(linePrefix(for: line.kind))
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundStyle(lineColor(for: line.kind))
                                        .frame(width: 12, alignment: .center)

                                    Text(line.text.isEmpty ? " " : line.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(lineColor(for: line.kind))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 1)
                                .padding(.horizontal, 8)
                                .background(lineBackground(for: line.kind))
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func linePrefix(for kind: ResponseDiffEngine.DiffLine.Kind) -> String {
        switch kind {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func lineColor(for kind: ResponseDiffEngine.DiffLine.Kind) -> Color {
        switch kind {
        case .unchanged: return .primary
        case .added: return .green
        case .removed: return .red
        }
    }

    private func lineBackground(for kind: ResponseDiffEngine.DiffLine.Kind) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
