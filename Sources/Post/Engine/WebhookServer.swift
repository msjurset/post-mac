import Foundation
import Network

@MainActor
public final class WebhookServer: ObservableObject {
    @Published public var isRunning: Bool = false
    @Published public var port: UInt16 = 9090
    @Published public var payloads: [WebhookPayload] = []
    @Published public var mockRules: [WebhookMockRule] = [
        WebhookMockRule(
            name: "GitHub Push Queued (202)",
            pathPrefix: "/webhook/github",
            statusCode: 202,
            responseHeaders: [
                KeyValueItem(key: "Content-Type", value: "application/json"),
                KeyValueItem(key: "X-Webhook-Worker", value: "github-bridge")
            ],
            responseBody: "{\"queued\":true,\"pipeline\":\"ci-main\"}",
            delayMs: 40,
            forwardToURL: "",
            isEnabled: true
        ),
        WebhookMockRule(
            name: "Simulated Rate Limit (429)",
            pathPrefix: "/webhook/rate-limit",
            statusCode: 429,
            responseHeaders: [
                KeyValueItem(key: "Content-Type", value: "application/json"),
                KeyValueItem(key: "Retry-After", value: "60")
            ],
            responseBody: "{\"error\":\"Too Many Requests\",\"retry_after\":60}",
            delayMs: 120,
            forwardToURL: "",
            isEnabled: true
        ),
        WebhookMockRule(
            name: "Chaos / Slow Upstream (503)",
            pathPrefix: "/webhook/chaos",
            statusCode: 503,
            responseHeaders: [
                KeyValueItem(key: "Content-Type", value: "application/json")
            ],
            responseBody: "{\"error\":\"upstream_timeout\",\"service\":\"billing-worker\"}",
            delayMs: 650,
            forwardToURL: "",
            isEnabled: true
        ),
        WebhookMockRule(
            name: "Default Catch-All (200 OK)",
            pathPrefix: "/webhook",
            statusCode: 200,
            responseHeaders: [KeyValueItem(key: "Content-Type", value: "application/json")],
            responseBody: "{\"status\":\"ok\",\"received\":true}",
            delayMs: 0,
            forwardToURL: "",
            isEnabled: true
        )
    ]

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
            isRunning = true
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

    public func addRule(_ rule: WebhookMockRule) {
        mockRules.append(rule)
    }

    public func removeRule(id: UUID) {
        mockRules.removeAll(where: { $0.id == id })
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveData(on: connection, accumulated: Data())
    }

    private func receiveData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self = self else {
                connection.cancel()
                return
            }

            var current = accumulated
            if let data = data, !data.isEmpty {
                current.append(data)
            }

            if current.isEmpty {
                connection.cancel()
                return
            }

            // Check if Content-Length indicates we need more bytes (up to 1 MB)
            let needed = self.bytesStillNeeded(in: current)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if needed > 0 && !isComplete && current.count < 1024 * 1024 {
                    self.receiveData(on: connection, accumulated: current)
                    return
                }
                self.processReceivedData(current, on: connection)
            }
        }
    }

    nonisolated private func bytesStillNeeded(in data: Data) -> Int {
        let separatorRange = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) ?? data.range(of: Data([0x0A, 0x0A]))
        guard let sep = separatorRange else {
            // Headers not complete yet
            return data.count < 1024 * 1024 ? 1 : 0
        }

        let headerData = data.subdata(in: 0..<sep.lowerBound)
        let headerStr = String(decoding: headerData, as: UTF8.self)

        for line in headerStr.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                if let contentLength = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let bodyReceived = data.count - sep.upperBound
                    return max(0, min(contentLength - bodyReceived, 1024 * 1024 - data.count))
                }
            }
        }
        return 0
    }

    private func processReceivedData(_ data: Data, on connection: NWConnection) {
        let rawHTTP = String(decoding: data, as: UTF8.self)
        var payload = parseHTTP(rawHTTP, clientEndpoint: connection.endpoint)

        let matchedRule = mockRules
            .filter { $0.isEnabled && payload.path.hasPrefix($0.pathPrefix) }
            .max(by: { $0.pathPrefix.count < $1.pathPrefix.count })
        let statusCode = matchedRule?.statusCode ?? 200
        let statusText = self.statusText(for: statusCode)
        let responseHeaders = matchedRule?.responseHeaders ?? [KeyValueItem(key: "Content-Type", value: "application/json")]
        let responseBody = matchedRule?.responseBody ?? "{\"status\":\"ok\"}"
        let delayMs = matchedRule?.delayMs ?? 0
        let forwardToURL = matchedRule?.forwardToURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        payload.responseStatusCode = statusCode
        if !forwardToURL.isEmpty {
            payload.forwardedTo = forwardToURL
        }

        self.payloads.insert(payload, at: 0)
        self.onPayloadReceived?(payload)

        // Asynchronously forward if rule has forwardToURL
        if !forwardToURL.isEmpty {
            let capturedPayload = payload
            Task {
                await self.forwardWebhook(capturedPayload, to: forwardToURL)
            }
        }

        // Send HTTP mock response (respecting delayMs if configured)
        Task {
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(delayMs))
            }

            let bodyData = responseBody.data(using: .utf8) ?? Data()
            var headerLines = ["HTTP/1.1 \(statusCode) \(statusText)"]
            var hasContentLength = false
            for h in responseHeaders where h.isEnabled && !h.key.isEmpty {
                if h.key.lowercased() == "content-length" {
                    hasContentLength = true
                }
                headerLines.append("\(h.key): \(h.value)")
            }
            if !hasContentLength {
                headerLines.append("Content-Length: \(bodyData.count)")
            }
            headerLines.append("Connection: close")

            let responseHeaderStr = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
            var fullData = responseHeaderStr.data(using: .utf8) ?? Data()
            fullData.append(bodyData)

            connection.send(content: fullData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    @discardableResult
    public func forwardWebhook(_ payload: WebhookPayload, to targetURLString: String) async -> Bool {
        guard let url = URL(string: targetURLString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = payload.method
        for header in payload.headers where header.isEnabled {
            let key = header.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && key.lowercased() != "host" && key.lowercased() != "content-length" {
                request.setValue(header.value, forHTTPHeaderField: key)
            }
        }
        if !payload.body.isEmpty {
            request.httpBody = payload.body.data(using: .utf8)
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse {
                return (200..<400).contains(httpRes.statusCode)
            }
            return true
        } catch {
            return false
        }
    }

    nonisolated private func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default:
            if code >= 200 && code < 300 { return "OK" }
            if code >= 400 && code < 500 { return "Client Error" }
            if code >= 500 { return "Server Error" }
            return "HTTP"
        }
    }

    nonisolated private func parseHTTP(_ raw: String, clientEndpoint: NWEndpoint) -> WebhookPayload {
        var method = "POST"
        var path = "/"
        var headers: [KeyValueItem] = []
        var body = ""

        let headerBodySplit: (headerPart: String, bodyPart: String) = {
            if let range = raw.range(of: "\r\n\r\n") {
                return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
            } else if let range = raw.range(of: "\n\n") {
                return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
            } else {
                return (raw, "")
            }
        }()

        let headerLines = headerBodySplit.headerPart.components(separatedBy: "\r\n")
        if let firstLine = headerLines.first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 {
                method = String(parts[0])
                path = String(parts[1])
            }
        }

        for i in 1..<headerLines.count {
            let line = headerLines[i]
            if line.isEmpty { continue }
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers.append(KeyValueItem(key: parts[0], value: parts[1], isEnabled: true))
            }
        }

        body = headerBodySplit.bodyPart.trimmingCharacters(in: .whitespacesAndNewlines)

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
