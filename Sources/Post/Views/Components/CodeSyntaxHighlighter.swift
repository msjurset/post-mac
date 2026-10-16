import SwiftUI
import AppKit

public enum CodeLanguage: String, Sendable {
    case json = "JSON"
    case bash = "cURL / Shell"
    case raw = "Raw Text"
}

public enum CodeColors {
    public static let comment = Color.gray
    public static let keyword = Color.purple
    public static let command = Color.blue
    public static let flag = Color.orange
    public static let string = Color.green
    public static let variable = Color.cyan
    public static let number = Color.yellow
    public static let operatorColor = Color.teal
    public static let templateVar = Color.pink
    public static let plain = Color.white.opacity(0.92)
    public static let background = Color(red: 0.10, green: 0.11, blue: 0.14)
    public static let nsBackground = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
}

public enum JSONHighlighter {
    private static let keyPattern = try! NSRegularExpression(pattern: #""([^"\\]|\\.)*"(?=\s*:)"#)
    private static let stringPattern = try! NSRegularExpression(pattern: #""([^"\\]|\\.)*""#)
    private static let numberPattern = try! NSRegularExpression(pattern: #"(?<=[:,\[\s])-?\d+(\.\d+)?([eE][+-]?\d+)?"#)
    private static let boolNullPattern = try! NSRegularExpression(pattern: #"\b(true|false|null)\b"#)
    private static let templatePattern = try! NSRegularExpression(pattern: #"\{\{[^}]+\}\}"#)
    private static let onePasswordPattern = try! NSRegularExpression(pattern: #"op://[^\s"',}]+"#)
    private static let queryParamKeyPattern = try! NSRegularExpression(pattern: #"(?:^|(?<=&))[A-Za-z0-9_.-]+(?==)"#)

    public static func apply(to attr: NSMutableAttributedString, enabled: Bool = true) {
        let fullText = attr.string
        let nsRange = NSRange(fullText.startIndex..., in: fullText)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let keyFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

        attr.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.92), range: nsRange)
        attr.addAttribute(.font, value: baseFont, range: nsRange)

        guard enabled else { return }

        // URL-encoded form data keys (param1=value1&param2=value2)
        for m in queryParamKeyPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemCyan, range: m.range)
            attr.addAttribute(.font, value: keyFont, range: m.range)
        }

        // Numbers
        for m in numberPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: m.range)
        }

        // Booleans and null
        for m in boolNullPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: m.range)
            attr.addAttribute(.font, value: keyFont, range: m.range)
        }

        // All strings first (green)
        for m in stringPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: m.range)
        }

        // Keys (strings followed by colon) override to cyan/purple
        for m in keyPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemCyan, range: m.range)
            attr.addAttribute(.font, value: keyFont, range: m.range)
        }

        // 1Password secret references (op://Vault/Item/field)
        for m in onePasswordPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: m.range)
            attr.addAttribute(.font, value: keyFont, range: m.range)
        }

        // Template variables ({{var}}) override everything
        for m in templatePattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
            attr.addAttribute(.font, value: keyFont, range: m.range)
        }
    }

    public static func highlightedString(_ code: String, enabled: Bool = true) -> AttributedString {
        let attr = NSMutableAttributedString(string: code)
        apply(to: attr, enabled: enabled)
        return (try? AttributedString(attr, including: \.appKit)) ?? AttributedString(code)
    }
}

public enum BashHighlighter {
    private static let flagPattern = try! NSRegularExpression(pattern: #"(?<=\s)-[A-Za-z-]+"#)
    private static let stringPattern = try! NSRegularExpression(pattern: #"'[^']*'|"(?:[^"\\]|\\.)*""#)
    private static let commandPattern = try! NSRegularExpression(pattern: #"^\s*(curl|http|jq|op|echo|export)\b"#, options: [.anchorsMatchLines])
    private static let templatePattern = try! NSRegularExpression(pattern: #"\{\{[^}]+\}\}"#)
    private static let onePasswordPattern = try! NSRegularExpression(pattern: #"op://[^\s"',}]+"#)

    public static func apply(to attr: NSMutableAttributedString, enabled: Bool = true) {
        let fullText = attr.string
        let nsRange = NSRange(fullText.startIndex..., in: fullText)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

        attr.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.92), range: nsRange)
        attr.addAttribute(.font, value: baseFont, range: nsRange)

        guard enabled else { return }

        for m in commandPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: m.range)
            attr.addAttribute(.font, value: boldFont, range: m.range)
        }

        for m in flagPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: m.range)
        }

        for m in stringPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: m.range)
        }

        for m in onePasswordPattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: m.range)
            attr.addAttribute(.font, value: boldFont, range: m.range)
        }

        for m in templatePattern.matches(in: fullText, range: nsRange) {
            attr.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
            attr.addAttribute(.font, value: boldFont, range: m.range)
        }
    }

    public static func highlightedString(_ code: String, enabled: Bool = true) -> AttributedString {
        let attr = NSMutableAttributedString(string: code)
        apply(to: attr, enabled: enabled)
        return (try? AttributedString(attr, including: \.appKit)) ?? AttributedString(code)
    }
}

public struct CodeBlockView: View {
    public let code: String
    public var language: CodeLanguage = .json
    public var showHeader: Bool = true
    public var enableSyntaxHighlighting: Bool = true

    @State private var copied: Bool = false

    public init(
        code: String,
        language: CodeLanguage = .json,
        showHeader: Bool = true,
        enableSyntaxHighlighting: Bool = true
    ) {
        self.code = code
        self.language = language
        self.showHeader = showHeader
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
    }

    private var highlightedAttributed: AttributedString {
        switch language {
        case .json, .raw:
            return JSONHighlighter.highlightedString(code, enabled: enableSyntaxHighlighting)
        case .bash:
            return BashHighlighter.highlightedString(code, enabled: enableSyntaxHighlighting)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(language.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(copied ? "Copied" : "Copy")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(copied ? .green : .white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))

                Divider()
                    .overlay(Color.white.opacity(0.08))
            }

            Text(highlightedAttributed)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CodeColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
