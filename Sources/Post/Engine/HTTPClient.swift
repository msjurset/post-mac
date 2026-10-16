import Foundation

public final class HTTPClient: Sendable {
    public static let shared = HTTPClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(request: HTTPRequest) async throws -> HTTPResponse {
        guard var url = request.fullURL else {
            throw NSError(domain: "HTTPClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL string: '\(request.url)'"])
        }

        // Apply query API key if applicable
        if request.auth.type == .apiKey && request.auth.apiKeyLocation == .query && !request.auth.apiKeyName.isEmpty {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: request.auth.apiKeyName, value: request.auth.apiKeyValue))
                components.queryItems = queryItems
                if let modifiedURL = components.url {
                    url = modifiedURL
                }
            }
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // Add headers
        for header in request.headers where header.isEnabled && !header.key.isEmpty {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        // Apply auth headers
        switch request.auth.type {
        case .none:
            break
        case .bearer:
            if !request.auth.bearerToken.isEmpty {
                urlRequest.setValue("Bearer \(request.auth.bearerToken)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            if !request.auth.basicUsername.isEmpty {
                let credentials = "\(request.auth.basicUsername):\(request.auth.basicPassword)"
                if let data = credentials.data(using: .utf8) {
                    urlRequest.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
            }
        case .apiKey:
            if request.auth.apiKeyLocation == .header && !request.auth.apiKeyName.isEmpty {
                urlRequest.setValue(request.auth.apiKeyValue, forHTTPHeaderField: request.auth.apiKeyName)
            }
        }

        // Add body if applicable
        if request.method != .get && request.method != .head {
            if request.bodyType == .json || request.bodyType == .raw || request.bodyType == .formData {
                if !request.bodyText.isEmpty {
                    urlRequest.httpBody = request.bodyText.data(using: .utf8)
                    if request.bodyType == .json && urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    } else if request.bodyType == .formData && urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
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
        return CodeGenerator.generate(for: request, format: .curl)
    }
}
