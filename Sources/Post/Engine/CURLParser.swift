import Foundation

public struct CURLParser {
    public static func parse(curlCommand: String) -> HTTPRequest? {
        let trimmed = curlCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("curl") else { return nil }

        var method: HTTPMethod = .get
        var urlString = ""
        var headers: [KeyValueItem] = []
        var bodyText = ""
        var bodyType: BodyType = .none

        // Tokenize while respecting quotes
        let tokens = tokenize(trimmed)
        var idx = 0

        while idx < tokens.count {
            let token = tokens[idx]

            if token == "curl" {
                idx += 1
                continue
            }

            if token == "-X" || token == "--request" {
                if idx + 1 < tokens.count {
                    let methodStr = tokens[idx + 1].uppercased()
                    if let parsedMethod = HTTPMethod(rawValue: methodStr) {
                        method = parsedMethod
                    }
                    idx += 2
                    continue
                }
            } else if token == "-H" || token == "--header" {
                if idx + 1 < tokens.count {
                    let headerLine = tokens[idx + 1]
                    let parts = headerLine.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        headers.append(KeyValueItem(key: parts[0], value: parts[1], isEnabled: true))
                    }
                    idx += 2
                    continue
                }
            } else if token == "-d" || token == "--data" || token == "--data-raw" || token == "--data-binary" {
                if idx + 1 < tokens.count {
                    bodyText = tokens[idx + 1]
                    if method == .get {
                        method = .post
                    }
                    bodyType = bodyText.trimmingCharacters(in: .whitespaces).hasPrefix("{") || bodyText.trimmingCharacters(in: .whitespaces).hasPrefix("[") ? .json : .raw
                    idx += 2
                    continue
                }
            } else if token.hasPrefix("http://") || token.hasPrefix("https://") {
                urlString = token
                idx += 1
                continue
            } else if !token.hasPrefix("-") && urlString.isEmpty {
                urlString = token
            }

            idx += 1
        }

        if urlString.isEmpty {
            return nil
        }

        return HTTPRequest(
            name: "Imported cURL",
            method: method,
            url: urlString,
            headers: headers,
            bodyType: bodyType,
            bodyText: bodyText
        )
    }

    private static func tokenize(_ command: String) -> [String] {
        var result: [String] = []
        var currentToken = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for char in command {
            if isEscaped {
                currentToken.append(char)
                isEscaped = false
                continue
            }

            if char == "\\" && !inSingleQuote {
                isEscaped = true
                continue
            }

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !currentToken.isEmpty {
                    result.append(currentToken)
                    currentToken = ""
                }
            } else {
                currentToken.append(char)
            }
        }

        if !currentToken.isEmpty {
            result.append(currentToken)
        }

        return result
    }
}
