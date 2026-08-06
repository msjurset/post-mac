import SwiftUI

struct ResponseView: View {
    let response: HTTPResponse?
    @State private var selectedResponseTab: ResponseTab = .body

    enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "Response Body"
        case headers = "Headers"

        var id: String { rawValue }
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
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(10)
                .background(.bar)

                Divider()

                switch selectedResponseTab {
                case .body:
                    ScrollView {
                        Text(response.formattedBody)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                case .headers:
                    List(response.headers) { h in
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

    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
