import SwiftUI

struct WebhookServerView: View {
    @ObservedObject var store: PostStore
    @ObservedObject var server: WebhookServer
    @State private var selectedPayloadID: UUID?
    @State private var payloadsListWidth: CGFloat = 260

    init(store: PostStore) {
        self.store = store
        self.server = store.webhookServer
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
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

                Button(action: {
                    store.webhookServer.clearPayloads()
                    selectedPayloadID = nil
                }) {
                    Image(systemName: "trash")
                }
                .focusable(false)
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.bar)

            Divider()

            // Main Webhook Inspector Split
            HStack(spacing: 0) {
                // Left Payload History List
                List(selection: $selectedPayloadID) {
                    ForEach(store.webhookServer.payloads) { payload in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(payload.method)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                                Text(payload.path)
                                    .font(.caption.bold())
                                    .monospaced()
                                Spacer()
                                Text(payload.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(payload.clientIP)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .tag(payload.id)
                    }
                }
                .frame(width: payloadsListWidth)
                .listStyle(.inset)

                DraggableDivider(width: $payloadsListWidth, minWidth: 180, maxWidth: 500)

                // Right Payload Inspector
                if let payload = store.webhookServer.payloads.first(where: { $0.id == selectedPayloadID }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("\(payload.method) \(payload.path)")
                                    .font(.title3.bold())
                                    .monospaced()
                                Spacer()
                                Text("From \(payload.clientIP)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Headers")
                                    .font(.headline)
                                ForEach(payload.headers) { h in
                                    HStack {
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

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Body Payload")
                                    .font(.headline)
                                Text(payload.formattedBody)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(16)
                    }
                } else {
                    EmptyStateView(
                        imageName: "empty_webhooks",
                        title: "Local Webhook Listener",
                        subtitle: store.webhookServer.isRunning
                            ? "Listening for webhooks on port \(String(store.webhookServer.port))...\nSend HTTP POST or GET requests to http://localhost:\(String(store.webhookServer.port))/webhook"
                            : "Start the local network server on port \(String(store.webhookServer.port)) to capture and inspect incoming webhooks in real time.",
                        primaryActionTitle: store.webhookServer.isRunning ? "Stop Server" : "Start Listener",
                        primaryActionIcon: store.webhookServer.isRunning ? "stop.fill" : "play.fill",
                        primaryAction: {
                            if store.webhookServer.isRunning {
                                store.webhookServer.stop()
                            } else {
                                store.webhookServer.start()
                            }
                        }
                    )
                }
            }
        }
    }
}
