import SwiftUI
import AppKit

// MARK: - Search Suggestion Item Model

public struct SearchSuggestionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let iconName: String
    public let isKey: Bool
    public let keyPrefix: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String = "magnifyingglass",
        isKey: Bool = false,
        keyPrefix: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.isKey = isKey
        self.keyPrefix = keyPrefix
    }

    public var text: String { title }
}

// MARK: - Token Span Helper

public struct TokenSpan: Equatable {
    public let range: Range<String.Index>
    public let intRange: Range<Int>
    public let text: String

    public init(range: Range<String.Index>, intRange: Range<Int>, text: String) {
        self.range = range
        self.intRange = intRange
        self.text = text
    }

    public static func span(in text: String, cursor: Int) -> TokenSpan {
        let utf16Count = text.utf16.count
        let clampedCursor = max(0, min(cursor, utf16Count))

        let targetIndex = text.utf16.index(
            text.utf16.startIndex,
            offsetBy: clampedCursor,
            limitedBy: text.utf16.endIndex
        ) ?? text.endIndex

        var startIndex = targetIndex
        while startIndex > text.startIndex {
            let prevIndex = text.index(before: startIndex)
            if text[prevIndex].isWhitespace {
                break
            }
            startIndex = prevIndex
        }

        var endIndex = targetIndex
        while endIndex < text.endIndex {
            if text[endIndex].isWhitespace {
                break
            }
            endIndex = text.index(after: endIndex)
        }

        let tokenText = String(text[startIndex..<endIndex])
        let startInt = text.utf16.distance(from: text.utf16.startIndex, to: startIndex)
        let endInt = text.utf16.distance(from: text.utf16.startIndex, to: endIndex)

        return TokenSpan(
            range: startIndex..<endIndex,
            intRange: startInt..<endInt,
            text: tokenText
        )
    }

    public static func usedValues(for key: String, in text: String, excludingCurrentSpan span: TokenSpan) -> Set<String> {
        var used = Set<String>()
        let lowerKey = key.lowercased()

        var current = text.startIndex
        while current < text.endIndex {
            while current < text.endIndex && text[current].isWhitespace {
                current = text.index(after: current)
            }
            if current >= text.endIndex { break }

            let tokenStart = current
            while current < text.endIndex && !text[current].isWhitespace {
                current = text.index(after: current)
            }
            let tokenEnd = current
            let tokenRange = tokenStart..<tokenEnd

            if tokenRange == span.range {
                continue
            }

            let tok = String(text[tokenRange])
            if let colonIdx = tok.firstIndex(of: ":") {
                let tokKey = String(tok[..<colonIdx]).lowercased()
                let tokVal = String(tok[tok.index(after: colonIdx)...])
                if tokKey == lowerKey && !tokVal.isEmpty {
                    used.insert(tokVal.lowercased())
                }
            }
        }

        return used
    }
}

// MARK: - Search Suggestion Engine

@MainActor
public final class SearchSuggestionEngine: ObservableObject {
    @Published public var suggestions: [SearchSuggestionItem] = []
    @Published public var activeIndex: Int = 0
    @Published public var isVisible: Bool = false

    public var currentCursor: Int = 0
    public var isProgrammaticEdit: Bool = false

    public static let supportedKeys: [(key: String, label: String, desc: String, icon: String)] = [
        ("method:", "method:", "Filter by HTTP method (GET, POST...)", "arrow.up.arrow.down"),
        ("status:", "status:", "Filter by response status code (200, 404...)", "checkmark.circle"),
        ("type:", "type:", "Filter by type (HTTP, Webhook, MCP)", "square.stack.3d.up"),
        ("host:", "host:", "Filter by target host or domain", "network"),
        ("collection:", "collection:", "Filter by saved request collection", "folder")
    ]

    public static let methodValues: [String] = [
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"
    ]

    public static let statusValues: [(code: String, text: String)] = [
        ("200", "200 OK"),
        ("201", "201 Created"),
        ("204", "204 No Content"),
        ("400", "400 Bad Request"),
        ("401", "401 Unauthorized"),
        ("403", "403 Forbidden"),
        ("404", "404 Not Found"),
        ("429", "429 Too Many Requests"),
        ("500", "500 Internal Server Error")
    ]

    public static let typeValues: [String] = [
        "HTTP", "Webhook", "MCP"
    ]

    public init() {}

    // MARK: - Event Handlers

    public func onCursorMoved(query: String, cursor: Int, store: PostStore) {
        currentCursor = cursor
        if isVisible {
            updateSuggestions(for: query, at: cursor, store: store, isExplicitTab: false)
        }
    }

    public func onQueryChanged(query: String, store: PostStore) {
        guard !isProgrammaticEdit else { return }
        updateSuggestions(for: query, at: currentCursor, store: store, isExplicitTab: false)
    }

    public func onTab(query: inout String, pendingCursor: inout Int?, store: PostStore) -> Bool {
        if !isVisible {
            updateSuggestions(for: query, at: currentCursor, store: store, isExplicitTab: true)
            if !suggestions.isEmpty {
                isVisible = true
                activeIndex = 0
                return true
            }
            return false
        }

        guard !suggestions.isEmpty else {
            isVisible = false
            return false
        }

        if suggestions.count > 1 {
            activeIndex = (activeIndex + 1) % suggestions.count
            return true
        }

        // Exactly 1 item: replace partial token without trailing space
        let item = suggestions[0]
        applySingleItemTabCompletion(item: item, in: &query, pendingCursor: &pendingCursor, store: store)
        return true
    }

    public func onShiftTab() -> Bool {
        guard isVisible && !suggestions.isEmpty else { return false }
        activeIndex = (activeIndex - 1 + suggestions.count) % suggestions.count
        return true
    }

    public func onDownArrow() -> Bool {
        guard isVisible && !suggestions.isEmpty else { return false }
        activeIndex = (activeIndex + 1) % suggestions.count
        return true
    }

    public func onUpArrow() -> Bool {
        guard isVisible && !suggestions.isEmpty else { return false }
        activeIndex = (activeIndex - 1 + suggestions.count) % suggestions.count
        return true
    }

    public func onCommit(query: inout String, pendingCursor: inout Int?, store: PostStore) -> Bool {
        guard isVisible && !suggestions.isEmpty else { return false }
        let item = suggestions[max(0, min(activeIndex, suggestions.count - 1))]
        commit(item: item, in: &query, pendingCursor: &pendingCursor, store: store)
        return true
    }

    public func dismiss() {
        isVisible = false
        suggestions = []
        activeIndex = 0
    }

    // MARK: - Commit & Completion Logic

    public func commit(item: SearchSuggestionItem, in query: inout String, pendingCursor: inout Int?, store: PostStore) {
        let span = TokenSpan.span(in: query, cursor: currentCursor)

        isProgrammaticEdit = true

        if item.isKey {
            // Commit key without trailing space, then immediately chain into values
            let keyText = item.title.hasSuffix(":") ? item.title : "\(item.title):"
            query.replaceSubrange(span.range, with: keyText)

            let newCursor = span.intRange.lowerBound + keyText.utf16.count
            currentCursor = newCursor
            pendingCursor = newCursor
            let updatedQuery = query

            updateSuggestions(for: updatedQuery, at: newCursor, store: store, isExplicitTab: true)
            isVisible = !suggestions.isEmpty
            activeIndex = 0

            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticEdit = false
            }
        } else {
            // Commit value with a trailing space and dismiss dropdown
            let prefix = item.keyPrefix.map { "\($0):" } ?? ""
            let fullToken = "\(prefix)\(item.title) "
            query.replaceSubrange(span.range, with: fullToken)

            let newCursor = span.intRange.lowerBound + fullToken.utf16.count
            currentCursor = newCursor
            pendingCursor = newCursor

            isVisible = false
            suggestions = []
            activeIndex = 0

            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticEdit = false
            }
        }
    }

    private func applySingleItemTabCompletion(item: SearchSuggestionItem, in query: inout String, pendingCursor: inout Int?, store: PostStore) {
        let span = TokenSpan.span(in: query, cursor: currentCursor)
        isProgrammaticEdit = true

        if item.isKey {
            let keyText = item.title.hasSuffix(":") ? item.title : "\(item.title):"
            query.replaceSubrange(span.range, with: keyText)

            let newCursor = span.intRange.lowerBound + keyText.utf16.count
            currentCursor = newCursor
            pendingCursor = newCursor
            let updatedQuery = query

            updateSuggestions(for: updatedQuery, at: newCursor, store: store, isExplicitTab: true)
            isVisible = !suggestions.isEmpty
            activeIndex = 0

            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticEdit = false
            }
        } else {
            let prefix = item.keyPrefix.map { "\($0):" } ?? ""
            let tokenWithoutSpace = "\(prefix)\(item.title)"
            query.replaceSubrange(span.range, with: tokenWithoutSpace)

            let newCursor = span.intRange.lowerBound + tokenWithoutSpace.utf16.count
            currentCursor = newCursor
            pendingCursor = newCursor
            let updatedQuery = query

            updateSuggestions(for: updatedQuery, at: newCursor, store: store, isExplicitTab: false)
            isVisible = !suggestions.isEmpty
            activeIndex = 0

            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticEdit = false
            }
        }
    }

    // MARK: - Suggestions Calculation

    private func updateSuggestions(for query: String, at cursor: Int, store: PostStore, isExplicitTab: Bool) {
        let span = TokenSpan.span(in: query, cursor: cursor)
        let token = span.text

        if let colonIdx = token.firstIndex(of: ":") {
            // Inside key:partial value completion
            let key = String(token[..<colonIdx]).lowercased()
            let partialValue = String(token[token.index(after: colonIdx)...])
            let used = TokenSpan.usedValues(for: key, in: query, excludingCurrentSpan: span)

            let candidateItems = valueCandidates(for: key, partial: partialValue, usedValues: used, store: store)
            self.suggestions = candidateItems
            self.isVisible = !candidateItems.isEmpty
            self.activeIndex = 0
        } else {
            // Key completion mode
            if isExplicitTab {
                let partialKey = token.lowercased()
                let items = Self.supportedKeys.compactMap { keyInfo -> SearchSuggestionItem? in
                    guard partialKey.isEmpty || keyInfo.key.lowercased().contains(partialKey) else {
                        return nil
                    }
                    return SearchSuggestionItem(
                        id: "key:\(keyInfo.key)",
                        title: keyInfo.label,
                        subtitle: keyInfo.desc,
                        iconName: keyInfo.icon,
                        isKey: true
                    )
                }
                self.suggestions = items
                self.isVisible = !items.isEmpty
                self.activeIndex = 0
            } else {
                // Auto-pop discipline: typing key without ':' does not auto-pop
                self.suggestions = []
                self.isVisible = false
                self.activeIndex = 0
            }
        }
    }

    private func valueCandidates(for key: String, partial: String, usedValues: Set<String>, store: PostStore) -> [SearchSuggestionItem] {
        let needle = partial.trimmingCharacters(in: .whitespaces).lowercased()

        switch key {
        case "method":
            return Self.methodValues.compactMap { method in
                let lower = method.lowercased()
                guard !usedValues.contains(lower) else { return nil }
                guard needle.isEmpty || lower.contains(needle) else { return nil }
                return SearchSuggestionItem(
                    id: "method:\(method)",
                    title: method,
                    subtitle: "HTTP Method",
                    iconName: "arrow.triangle.2.circlepath",
                    isKey: false,
                    keyPrefix: "method"
                )
            }

        case "status":
            return Self.statusValues.compactMap { item in
                let lower = item.code.lowercased()
                guard !usedValues.contains(lower) else { return nil }
                guard needle.isEmpty || lower.contains(needle) || item.text.lowercased().contains(needle) else { return nil }
                return SearchSuggestionItem(
                    id: "status:\(item.code)",
                    title: item.code,
                    subtitle: item.text,
                    iconName: "number.circle",
                    isKey: false,
                    keyPrefix: "status"
                )
            }

        case "type":
            return Self.typeValues.compactMap { type in
                let lower = type.lowercased()
                guard !usedValues.contains(lower) else { return nil }
                guard needle.isEmpty || lower.contains(needle) else { return nil }
                return SearchSuggestionItem(
                    id: "type:\(type)",
                    title: type,
                    subtitle: "Event Type",
                    iconName: "tag",
                    isKey: false,
                    keyPrefix: "type"
                )
            }

        case "host":
            var hosts = Set<String>(["localhost", "httpbin.org", "jsonplaceholder.typicode.com"])
            for req in store.requests {
                if let url = URL(string: req.url), let h = url.host, !h.isEmpty {
                    hosts.insert(h)
                }
            }
            for item in store.history {
                if let req = item.requestData, let url = URL(string: req.url), let h = url.host, !h.isEmpty {
                    hosts.insert(h)
                } else if let url = URL(string: item.subtitle), let h = url.host, !h.isEmpty {
                    hosts.insert(h)
                }
            }
            return hosts.sorted().compactMap { host in
                let lower = host.lowercased()
                guard !usedValues.contains(lower) else { return nil }
                guard needle.isEmpty || lower.contains(needle) else { return nil }
                return SearchSuggestionItem(
                    id: "host:\(host)",
                    title: host,
                    subtitle: "Host / Domain",
                    iconName: "network",
                    isKey: false,
                    keyPrefix: "host"
                )
            }

        case "collection":
            let collectionNames = store.collections.map { $0.name }
            return collectionNames.compactMap { col in
                let lower = col.lowercased()
                guard !usedValues.contains(lower) else { return nil }
                guard needle.isEmpty || lower.contains(needle) else { return nil }
                return SearchSuggestionItem(
                    id: "collection:\(col)",
                    title: col,
                    subtitle: "Collection",
                    iconName: "folder.fill",
                    isKey: false,
                    keyPrefix: "collection"
                )
            }

        default:
            return []
        }
    }
}

// MARK: - Search Suggestion Dropdown View

public struct SearchSuggestionDropdownView: View {
    @ObservedObject var engine: SearchSuggestionEngine
    var onSelect: (SearchSuggestionItem) -> Void

    public init(engine: SearchSuggestionEngine, onSelect: @escaping (SearchSuggestionItem) -> Void) {
        self.engine = engine
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(engine.suggestions.enumerated()), id: \.element.id) { index, item in
                            SuggestionRowView(
                                item: item,
                                isHighlighted: index == engine.activeIndex,
                                onHover: {
                                    engine.activeIndex = index
                                },
                                onSelect: {
                                    onSelect(item)
                                }
                            )
                            .id(index)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: min(220, CGFloat(engine.suggestions.count * 32 + 10)))
                .onChange(of: engine.activeIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}

private struct SuggestionRowView: View {
    let item: SearchSuggestionItem
    let isHighlighted: Bool
    let onHover: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(item.title)
                    .font(.system(.caption, design: item.isKey ? .monospaced : .default).weight(item.isKey ? .semibold : .medium))
                    .foregroundStyle(isHighlighted ? Color.primary : Color.primary.opacity(0.9))

                Spacer()

                if let sub = item.subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? Color.secondary : Color.secondary.opacity(0.65))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
    }
}
