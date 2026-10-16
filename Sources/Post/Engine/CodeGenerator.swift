import Foundation

public enum CodeExportFormat: String, CaseIterable, Identifiable, Sendable {
    case curl = "cURL"
    case go = "Go (net/http)"
    case swift = "Swift (URLSession)"
    case python = "Python (httpx)"

    public var id: String { rawValue }
}

public struct CodeGenerator: Sendable {
    public static func generate(for request: HTTPRequest, format: CodeExportFormat) -> String {
        switch format {
        case .curl:
            return generateCURL(for: request)
        case .go:
            return generateGo(for: request)
        case .swift:
            return generateSwift(for: request)
        case .python:
            return generatePython(for: request)
        }
    }

    public static func effectiveURL(for request: HTTPRequest) -> String {
        guard var components = URLComponents(string: request.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return request.url
        }
        var existingItems = components.queryItems ?? []
        let activeParams = request.queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        for param in activeParams {
            existingItems.append(URLQueryItem(name: param.key, value: param.value))
        }
        if request.auth.type == .apiKey && request.auth.apiKeyLocation == .query && !request.auth.apiKeyName.isEmpty {
            existingItems.append(URLQueryItem(name: request.auth.apiKeyName, value: request.auth.apiKeyValue))
        }
        if !existingItems.isEmpty {
            components.queryItems = existingItems
        }
        return components.url?.absoluteString ?? request.url
    }

    public static func effectiveHeaders(for request: HTTPRequest) -> [(key: String, value: String)] {
        var headers: [(key: String, value: String)] = []

        for h in request.headers where h.isEnabled && !h.key.isEmpty {
            headers.append((key: h.key, value: h.value))
        }

        switch request.auth.type {
        case .none:
            break
        case .bearer:
            if !request.auth.bearerToken.isEmpty {
                headers.append((key: "Authorization", value: "Bearer \(request.auth.bearerToken)"))
            }
        case .basic:
            if !request.auth.basicUsername.isEmpty {
                let credentials = "\(request.auth.basicUsername):\(request.auth.basicPassword)"
                let base64 = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
                headers.append((key: "Authorization", value: "Basic \(base64)"))
            }
        case .apiKey:
            if request.auth.apiKeyLocation == .header && !request.auth.apiKeyName.isEmpty {
                headers.append((key: request.auth.apiKeyName, value: request.auth.apiKeyValue))
            }
        }

        let hasContentType = headers.contains { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }
        if !hasContentType && request.method != .get && request.method != .head && !request.bodyText.isEmpty {
            if request.bodyType == .json {
                headers.append((key: "Content-Type", value: "application/json"))
            } else if request.bodyType == .formData {
                headers.append((key: "Content-Type", value: "application/x-www-form-urlencoded"))
            }
        }

        return headers
    }

    private static func generateCURL(for request: HTTPRequest) -> String {
        let url = effectiveURL(for: request)
        var parts: [String] = ["curl -X \(request.method.rawValue)"]

        for (k, v) in effectiveHeaders(for: request) {
            let escapedVal = v.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("  -H '\(k): \(escapedVal)'")
        }

        if request.method != .get && request.method != .head && !request.bodyText.isEmpty && request.bodyType != .none {
            let escapedBody = request.bodyText.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("  -d '\(escapedBody)'")
        }

        parts.append("  '\(url)'")
        return parts.joined(separator: " \\\n")
    }

    private static func generateGo(for request: HTTPRequest) -> String {
        let url = effectiveURL(for: request)
        let headers = effectiveHeaders(for: request)
        let hasBody = request.method != .get && request.method != .head && !request.bodyText.isEmpty && request.bodyType != .none

        var code = "package main\n\nimport (\n\t\"context\"\n\t\"fmt\"\n\t\"io\"\n\t\"net/http\"\n"
        if hasBody {
            code += "\t\"strings\"\n"
        }
        code += ")\n\nfunc main() {\n\tctx := context.Background()\n\turl := \"\(url)\"\n\n"

        if hasBody {
            let escapedBody = request.bodyText.replacingOccurrences(of: "`", with: "` + \"`\" + `")
            code += "\tbody := strings.NewReader(`\(escapedBody)`)\n"
            code += "\treq, err := http.NewRequestWithContext(ctx, \"\(request.method.rawValue)\", url, body)\n"
        } else {
            code += "\treq, err := http.NewRequestWithContext(ctx, \"\(request.method.rawValue)\", url, nil)\n"
        }

        code += "\tif err != nil {\n\t\tpanic(err)\n\t}\n\n"

        for (k, v) in headers {
            let escapedV = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            code += "\treq.Header.Set(\"\(k)\", \"\(escapedV)\")\n"
        }

        code += """

\tresp, err := http.DefaultClient.Do(req)
\tif err != nil {
\t\tpanic(err)
\t}
\tdefer resp.Body.Close()

\trespBody, err := io.ReadAll(resp.Body)
\tif err != nil {
\t\tpanic(err)
\t}

\tfmt.Println(resp.Status)
\tfmt.Println(string(respBody))
}
"""
        return code
    }

    private static func generateSwift(for request: HTTPRequest) -> String {
        let url = effectiveURL(for: request)
        let headers = effectiveHeaders(for: request)
        let hasBody = request.method != .get && request.method != .head && !request.bodyText.isEmpty && request.bodyType != .none

        var code = """
import Foundation

func executeRequest() async throws {
    guard let url = URL(string: "\(url)") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "\(request.method.rawValue)"

"""

        for (k, v) in headers {
            let escapedV = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            code += "    request.setValue(\"\(escapedV)\", forHTTPHeaderField: \"\(k)\")\n"
        }

        if hasBody {
            let escapedBody = request.bodyText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
            code += "\n    let bodyString = \"\"\"\n\(escapedBody)\n\"\"\"\n"
            code += "    request.httpBody = bodyString.data(using: .utf8)\n"
        }

        code += """

    let (data, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse {
        print("Status: \\(httpResponse.statusCode)")
    }
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}
"""
        return code
    }

    private static func generatePython(for request: HTTPRequest) -> String {
        let url = effectiveURL(for: request)
        let headers = effectiveHeaders(for: request)
        let hasBody = request.method != .get && request.method != .head && !request.bodyText.isEmpty && request.bodyType != .none

        var code = "import httpx\n\nurl = \"\(url)\"\n"

        if !headers.isEmpty {
            code += "headers = {\n"
            for (k, v) in headers {
                let escapedV = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                code += "    \"\(k)\": \"\(escapedV)\",\n"
            }
            code += "}\n\n"
        } else {
            code += "headers = {}\n\n"
        }

        if hasBody {
            let escapedBody = request.bodyText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
            code += "content = \"\"\"\(escapedBody)\"\"\"\n\n"
            code += "response = httpx.request(\n"
            code += "    method=\"\(request.method.rawValue)\",\n"
            code += "    url=url,\n"
            code += "    headers=headers,\n"
            code += "    content=content.encode(\"utf-8\"),\n"
            code += ")\n"
        } else {
            code += "response = httpx.request(\n"
            code += "    method=\"\(request.method.rawValue)\",\n"
            code += "    url=url,\n"
            code += "    headers=headers,\n"
            code += ")\n"
        }

        code += """

print(response.status_code)
print(response.text)
"""
        return code
    }
}

public struct JSONPathEvaluator: Sendable {
    public static func evaluate(jsonString: String, path: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }

        var query = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty || query == "$" || query == "@" {
            return formatOutput(root)
        }

        if query.hasPrefix("$.") {
            query = String(query.dropFirst(2))
        } else if query.hasPrefix("$") {
            query = String(query.dropFirst(1))
        }

        if query.hasPrefix(".") {
            query = String(query.dropFirst(1))
        }

        if query.isEmpty {
            return formatOutput(root)
        }

        let tokens = parseTokens(from: query)
        guard !tokens.isEmpty else {
            return formatOutput(root)
        }

        if let direct = traverse(root: root, tokens: tokens) {
            return formatOutput(direct)
        }

        // Fallback to recursive key search
        if let firstMatch = recursiveSearch(in: root, key: tokens[0]) {
            if tokens.count == 1 {
                return formatOutput(firstMatch)
            }
            if let subResult = traverse(root: firstMatch, tokens: Array(tokens.dropFirst())) {
                return formatOutput(subResult)
            }
        }

        return nil
    }

    private static func traverse(root: Any, tokens: [String]) -> Any? {
        var current: Any? = root

        for token in tokens {
            guard let curr = current else { return nil }

            if let dict = curr as? [String: Any] {
                if let val = dict[token] {
                    current = val
                } else {
                    return nil
                }
            } else if let arr = curr as? [Any] {
                if let idx = Int(token), idx >= 0 && idx < arr.count {
                    current = arr[idx]
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        return current
    }

    private static func recursiveSearch(in value: Any, key: String) -> Any? {
        if let dict = value as? [String: Any] {
            if let match = dict[key] {
                return match
            }
            for (_, val) in dict {
                if let result = recursiveSearch(in: val, key: key) {
                    return result
                }
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                if let result = recursiveSearch(in: item, key: key) {
                    return result
                }
            }
        }
        return nil
    }

    private static func parseTokens(from path: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inBracket = false
        var inQuote = false
        var quoteChar: Character = "'"

        for char in path {
            if inQuote {
                if char == quoteChar {
                    inQuote = false
                } else {
                    current.append(char)
                }
            } else if inBracket {
                if char == "'" || char == "\"" {
                    inQuote = true
                    quoteChar = char
                } else if char == "]" {
                    inBracket = false
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        result.append(trimmed)
                        current = ""
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "[" {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        result.append(trimmed)
                        current = ""
                    }
                    inBracket = true
                } else if char == "." {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        result.append(trimmed)
                        current = ""
                    }
                } else {
                    current.append(char)
                }
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result.append(trimmed)
        }
        return result
    }

    private static func formatOutput(_ value: Any) -> String? {
        if JSONSerialization.isValidJSONObject(value) {
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }

        if let str = value as? String {
            return str
        }
        if let boolVal = value as? Bool {
            return boolVal ? "true" : "false"
        }
        if let num = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num as CFTypeRef) {
                return (num as! Bool) ? "true" : "false"
            }
            return num.stringValue
        }
        if value is NSNull {
            return "null"
        }
        return String(describing: value)
    }
}

public struct ResponseDiffEngine: Sendable {
    public struct DiffLine: Identifiable, Sendable {
        public let id: UUID
        public let kind: Kind
        public let lineNumber: Int?
        public let text: String

        public enum Kind: Sendable {
            case unchanged
            case added
            case removed
        }

        public init(id: UUID = UUID(), kind: Kind, lineNumber: Int?, text: String) {
            self.id = id
            self.kind = kind
            self.lineNumber = lineNumber
            self.text = text
        }
    }

    public static func diff(old: String, new: String) -> [DiffLine] {
        if old.isEmpty && new.isEmpty {
            return []
        }

        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        let m = oldLines.count
        let n = newLines.count

        if m * n > 2_000_000 {
            var result: [DiffLine] = []
            let count = max(m, n)
            for i in 0..<count {
                if i < m && i < n {
                    if oldLines[i] == newLines[i] {
                        result.append(DiffLine(kind: .unchanged, lineNumber: i + 1, text: newLines[i]))
                    } else {
                        result.append(DiffLine(kind: .removed, lineNumber: nil, text: oldLines[i]))
                        result.append(DiffLine(kind: .added, lineNumber: i + 1, text: newLines[i]))
                    }
                } else if i < n {
                    result.append(DiffLine(kind: .added, lineNumber: i + 1, text: newLines[i]))
                } else {
                    result.append(DiffLine(kind: .removed, lineNumber: nil, text: oldLines[i]))
                }
            }
            return result
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0..<m {
            for j in 0..<n {
                if oldLines[i] == newLines[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var i = m
        var j = n
        var reversedDiff: [DiffLine] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                reversedDiff.append(DiffLine(kind: .unchanged, lineNumber: j, text: newLines[j - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                reversedDiff.append(DiffLine(kind: .added, lineNumber: j, text: newLines[j - 1]))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                reversedDiff.append(DiffLine(kind: .removed, lineNumber: nil, text: oldLines[i - 1]))
                i -= 1
            }
        }

        return reversedDiff.reversed()
    }
}
