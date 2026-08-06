import Foundation
import Network

@MainActor
public final class WebhookServer: ObservableObject {
    @Published public var isRunning: Bool = false
    @Published public var port: UInt16 = 9090
    @Published public var payloads: [WebhookPayload] = []

    private var listener: NWListener?
    public var onPayloadReceived: ((WebhookPayload) -> Void)?

    public init(port: UInt16 = 9090) {
        self.port = port
    }

    public func start() {
        guard !isRunning else { return }

        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: port)
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: nwPort)

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .main)
        } catch {
            isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    public func clearPayloads() {
        payloads.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            let rawHTTP = String(decoding: data, as: UTF8.self)
            let payload = self.parseHTTP(rawHTTP, clientEndpoint: connection.endpoint)

            Task { @MainActor in
                self.payloads.insert(payload, at: 0)
                self.onPayloadReceived?(payload)
            }

            // Respond 200 OK
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    nonisolated private func parseHTTP(_ raw: String, clientEndpoint: NWEndpoint) -> WebhookPayload {
        let lines = raw.components(separatedBy: "\r\n")
        var method = "POST"
        var path = "/"
        var headers: [KeyValueItem] = []
        var body = ""

        if let firstLine = lines.first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 {
                method = String(parts[0])
                path = String(parts[1])
            }
        }

        var inBody = false
        var bodyLines: [String] = []

        for i in 1..<lines.count {
            let line = lines[i]
            if inBody {
                bodyLines.append(line)
            } else if line.isEmpty {
                inBody = true
            } else {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    headers.append(KeyValueItem(key: parts[0], value: parts[1], isEnabled: true))
                }
            }
        }

        body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var clientIP = "127.0.0.1"
        if case let .hostPort(host, _) = clientEndpoint {
            clientIP = host.debugDescription
        }

        return WebhookPayload(
            timestamp: Date(),
            method: method,
            path: path,
            headers: headers,
            body: body,
            clientIP: clientIP
        )
    }
}
