import Foundation

public final class HTTPClient: Sendable {
    public static let shared = HTTPClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = request.fullURL else {
            throw NSError(domain: "HTTPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL string: '\(request.url)'"])
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // Add headers
        for header in request.headers where header.isEnabled && !header.key.isEmpty {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        // Add body if applicable
        if request.method != .get && request.method != .head {
            if request.bodyType == .json || request.bodyType == .raw {
                if !request.bodyText.isEmpty {
                    urlRequest.httpBody = request.bodyText.data(using: .utf8)
                    if request.bodyType == .json && urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await session.data(for: urlRequest)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 200
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)

        var responseHeaders: [KeyValueItem] = []
        if let allHeaderFields = httpResponse?.allHeaderFields {
            for (key, value) in allHeaderFields {
                responseHeaders.append(KeyValueItem(key: String(describing: key), value: String(describing: value), isEnabled: true))
            }
        }

        let bodyString = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        return HTTPResponse(
            requestId: request.id,
            statusCode: statusCode,
            statusText: statusText.capitalized,
            headers: responseHeaders,
            bodyText: bodyString,
            responseTimeMs: durationMs,
            responseSizeBytes: Int64(data.count),
            timestamp: Date()
        )
    }

    /// Convert HTTPRequest to a runnable cURL command string
    public func exportToCURL(request: HTTPRequest) -> String {
        guard let url = request.fullURL else { return "curl '\(request.url)'" }
        var parts: [String] = ["curl -X \(request.method.rawValue)"]

        for header in request.headers where header.isEnabled && !header.key.isEmpty {
            let escapedVal = header.value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(header.key): \(escapedVal)'")
        }

        if request.method != .get && request.method != .head && !request.bodyText.isEmpty {
            let escapedBody = request.bodyText.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escapedBody)'")
        }

        parts.append("'\(url.absoluteString)'")
        return parts.joined(separator: " \\\n  ")
    }
}
