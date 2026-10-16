import SwiftUI
import AppKit
import Observation
import VimEngine

public enum EditorMode: String, Codable, CaseIterable, Sendable {
    case standard
    case vim
}

@Observable
@MainActor
public final class VimModeController {
    public var currentMode: EditorMode = .standard
    public var engine: VimEngine?
    public var badgeText: String = "VIM:N"
    public weak var activeTextView: NSTextView?

    public var isVimActive: Bool {
        currentMode == .vim && engine != nil
    }

    public var modeLabel: String {
        guard isVimActive else { return "" }
        return badgeText
    }

    public init() {
        // Always start in standard mode (VIM=OFF). Enabling Vim support in Settings
        // only exposes the :_ corner watermark toggle and /vim slash command.
        self.currentMode = .standard
        self.engine = nil
    }

    public func toggleVim() {
        if currentMode == .vim {
            disableVim()
        } else {
            enableVim()
        }
    }

    public func enableVim() {
        let e = VimEngine()
        e.onExit = { [weak self] in
            Task { @MainActor in
                self?.disableVim()
            }
        }
        e.onSubmit = {
            NotificationCenter.default.post(name: .vimSaveRequested, object: nil)
        }
        let refresh: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.badgeText = self.engine?.badge ?? "VIM:N"
                self.activeTextView?.needsDisplay = true
            }
        }
        e.onSubmodeChanged = refresh
        e.onCommandBufferChanged = refresh
        self.badgeText = e.badge
        self.engine = e
        self.currentMode = .vim
        (self.activeTextView as? VimHostTextView)?.updateExclusionPaths()
        self.activeTextView?.needsDisplay = true
    }

    public func disableVim() {
        self.engine = nil
        self.currentMode = .standard
        self.badgeText = "VIM:N"
        (self.activeTextView as? VimHostTextView)?.updateExclusionPaths()
        self.activeTextView?.needsDisplay = true
    }
}

extension Notification.Name {
    public static let vimSaveRequested = Notification.Name("post.vimSaveRequested")
}

public struct VimWatermarkButton: View {
    public var controller: VimModeController

    public init(controller: VimModeController) {
        self.controller = controller
    }

    public var body: some View {
        Button {
            controller.toggleVim()
        } label: {
            Text(":_")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .baselineOffset(-1)
                .tracking(-0.5)
                .foregroundStyle(controller.isVimActive ? Color.purple : Color.white.opacity(0.45))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(controller.isVimActive ? "Vim active — click to exit" : "Enable Vim mode for this field (or type /vim)")
    }
}

public struct VimModeBadge: View {
    public var controller: VimModeController
    @State private var showHelp = false

    public init(controller: VimModeController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.isVimActive {
            HStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text(controller.modeLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(badgeColor)

                    Button {
                        controller.disableVim()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(badgeColor.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Exit Vim mode (or :q)")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.18))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(badgeColor.opacity(0.45), lineWidth: 0.5)
                )

                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Vim mode keybinding reference")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    VimCheatsheetView()
                }
            }
        }
    }

    private var badgeColor: Color {
        let label = controller.modeLabel
        if label.hasPrefix("VIM:I") {
            return .green
        } else if label.hasPrefix("VIM:V") {
            return .orange
        } else if label.hasPrefix(":") || label.hasPrefix("/") {
            return .blue
        }
        return .purple
    }
}

public struct VimCheatsheetView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Vim Mode Cheatsheet")
                        .font(.headline)
                    Spacer()
                    Text("Esc to exit insert mode")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                section("Movement (Normal Mode)") {
                    row("h j k l", "left / down / up / right")
                    row("w / b", "next / previous word start")
                    row("e / ge", "word end / previous word end")
                    row("0 / $", "line start / line end")
                    row("gg / G", "buffer top / buffer bottom")
                    row("Ctrl-d / Ctrl-u", "half-page down / up")
                }

                section("Insert Mode") {
                    row("i / a", "insert before / after cursor")
                    row("I / A", "insert at line start / line end")
                    row("o / O", "open new line below / above")
                    row("Esc", "exit insert mode (return to normal)")
                }

                section("Editing & Deleting") {
                    row("x", "delete character under cursor")
                    row("dd", "delete entire line")
                    row("dw / de", "delete word / through word end")
                    row("d$", "delete to line end")
                    row("cc / cw", "change line / change word")
                    row("u", "undo last edit")
                    row("r<char>", "replace character with <char>")
                }

                section("Yank & Paste") {
                    row("yy", "yank (copy) current line")
                    row("yw", "yank word")
                    row("p / P", "paste after / before cursor")
                }

                section("Visual Mode") {
                    row("v / V", "enter char-wise / line-wise visual mode")
                    row("d / x", "delete visual selection")
                    row("y", "yank visual selection")
                    row("Esc", "exit visual mode")
                }

                section("Commands & Exit") {
                    row("/<term>", "search text forward (Enter jumps, n repeats)")
                    row(":w", "save workspace")
                    row(":q / :wq", "exit vim mode / save and exit")
                }
            }
            .padding(16)
        }
        .frame(width: 380, height: 420)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ key: String, _ desc: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(.caption, design: .monospaced).bold())
                .frame(width: 90, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

public struct SlashCommand: Identifiable, Sendable {
    public let id: String
    public let trigger: String
    public let label: String
    public let description: String
    public let icon: String

    public init(trigger: String, label: String, description: String, icon: String) {
        self.id = trigger
        self.trigger = trigger
        self.label = label
        self.description = description
        self.icon = icon
    }

    public static func availableCommands(vimEnabled: Bool) -> [SlashCommand] {
        var cmds: [SlashCommand] = []
        if vimEnabled {
            cmds.append(
                SlashCommand(
                    trigger: "/vim",
                    label: "Vim Mode",
                    description: "Toggle Vim normal mode",
                    icon: "terminal"
                )
            )
        }
        cmds.append(contentsOf: [
            SlashCommand(
                trigger: "/pretty",
                label: "Format JSON",
                description: "Pretty-print JSON payload",
                icon: "curlybraces"
            ),
            SlashCommand(
                trigger: "/json",
                label: "JSON Template",
                description: "Insert sample JSON object",
                icon: "doc.badge.gearshape"
            ),
            SlashCommand(
                trigger: "/graphql",
                label: "GraphQL Query",
                description: "Insert GraphQL query + variables",
                icon: "point.3.connected.trianglepath.dotted"
            ),
            SlashCommand(
                trigger: "/uuid",
                label: "UUID v4",
                description: "Insert random UUID string",
                icon: "number.square"
            ),
            SlashCommand(
                trigger: "/iso8601",
                label: "ISO-8601 Date",
                description: "Insert current UTC timestamp",
                icon: "calendar.badge.clock"
            ),
            SlashCommand(
                trigger: "/timestamp",
                label: "Epoch Seconds",
                description: "Insert Unix epoch timestamp",
                icon: "clock"
            ),
            SlashCommand(
                trigger: "/op",
                label: "1Password Ref",
                description: "Insert op://Vault/Item/field URI",
                icon: "key.fill"
            ),
            SlashCommand(
                trigger: "/env",
                label: "Env Variable",
                description: "Insert {{variable}} placeholder",
                icon: "globe"
            ),
            SlashCommand(
                trigger: "/clear",
                label: "Clear",
                description: "Clear entire editor buffer",
                icon: "trash"
            ),
        ])
        return cmds
    }

    public static func match(for prefix: String, vimEnabled: Bool) -> [SlashCommand] {
        let lower = prefix.lowercased()
        guard lower.hasPrefix("/") else { return [] }
        return availableCommands(vimEnabled: vimEnabled).filter { cmd in
            lower == "/" || cmd.trigger.lowercased().hasPrefix(lower)
        }
    }
}

public struct SlashSuggestionView: View {
    public let prefix: String
    public let vimEnabled: Bool
    public let selectedIndex: Int
    public let onSelect: (SlashCommand) -> Void

    public init(
        prefix: String,
        vimEnabled: Bool = true,
        selectedIndex: Int = 0,
        onSelect: @escaping (SlashCommand) -> Void
    ) {
        self.prefix = prefix
        self.vimEnabled = vimEnabled
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    private var matches: [SlashCommand] {
        SlashCommand.match(for: prefix, vimEnabled: vimEnabled)
    }

    public var body: some View {
        let items = matches
        if !items.isEmpty {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, cmd in
                            let isSelected = idx == min(max(0, selectedIndex), items.count - 1)
                            Button {
                                onSelect(cmd)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cmd.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : .purple)
                                    Text(cmd.trigger)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                    Text(cmd.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.purple : Color.purple.opacity(0.14))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(isSelected ? Color.purple : Color.purple.opacity(0.35), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                    }
                }

                Spacer(minLength: 4)

                Text("Tab cycle · Enter select · Esc dismiss")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        }
    }
}

public struct VimAwareEditor: View {
    @Binding public var text: String
    public var placeholder: String
    public var language: CodeLanguage
    public var minHeight: CGFloat
    public var enableSlashCommands: Bool
    public var enableVimEditor: Bool
    public var enableSyntaxHighlighting: Bool

    @State private var vimController = VimModeController()
    @State private var slashPrefix: String = ""
    @State private var slashSelectedIndex: Int = 0

    public init(
        text: Binding<String>,
        placeholder: String = "",
        language: CodeLanguage = .json,
        minHeight: CGFloat = 110,
        enableSlashCommands: Bool = true,
        enableVimEditor: Bool = true,
        enableSyntaxHighlighting: Bool = true
    ) {
        self._text = text
        self.placeholder = placeholder
        self.language = language
        self.minHeight = minHeight
        self.enableSlashCommands = enableSlashCommands
        self.enableVimEditor = enableVimEditor
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
    }

    private var matchingSlashCommands: [SlashCommand] {
        guard enableSlashCommands, !slashPrefix.isEmpty else { return [] }
        return SlashCommand.match(for: slashPrefix, vimEnabled: enableVimEditor)
    }

    private var isShowingSlashBar: Bool {
        !matchingSlashCommands.isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                VimTextViewRepresentable(
                    text: $text,
                    slashPrefix: $slashPrefix,
                    slashSelectedIndex: $slashSelectedIndex,
                    controller: vimController,
                    language: language,
                    enableSlashCommands: enableSlashCommands,
                    enableVimEditor: enableVimEditor,
                    enableSyntaxHighlighting: enableSyntaxHighlighting,
                    onExecuteSlash: executeSlashCommand
                )

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if enableVimEditor && vimController.isVimActive {
                    VimModeBadge(controller: vimController)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if enableVimEditor {
                    VimWatermarkButton(controller: vimController)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }

            // Never reserve a permanent line for slash command pills:
            // Only render and grow the editor container while a /slash command is in progress.
            if isShowingSlashBar {
                Divider()
                    .overlay(Color.white.opacity(0.12))
                SlashSuggestionView(
                    prefix: slashPrefix,
                    vimEnabled: enableVimEditor,
                    selectedIndex: slashSelectedIndex
                ) { cmd in
                    executeSlashCommand(cmd)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Dynamically grow the field height by 32pt when slash pill bar is active
        .frame(minHeight: minHeight + (isShowingSlashBar ? 32 : 0))
        .animation(.snappy(duration: 0.16), value: isShowingSlashBar)
        .background(CodeColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    vimController.isVimActive ? Color.purple.opacity(0.65) : Color.white.opacity(0.14),
                    lineWidth: vimController.isVimActive ? 1.5 : 1.0
                )
        )
        .onChange(of: enableVimEditor) { _, enabled in
            if !enabled && vimController.isVimActive {
                vimController.disableVim()
            }
        }
        .onChange(of: enableSlashCommands) { _, enabled in
            if !enabled {
                slashPrefix = ""
                slashSelectedIndex = 0
            }
        }
    }

    private func executeSlashCommand(_ cmd: SlashCommand) {
        var current = text
        if let range = current.range(of: slashPrefix, options: [.backwards, .caseInsensitive]) {
            current.removeSubrange(range)
        }
        slashPrefix = ""
        slashSelectedIndex = 0

        switch cmd.trigger {
        case "/vim":
            text = current
            if enableVimEditor {
                vimController.toggleVim()
            }
        case "/pretty":
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let formatted = String(data: pretty, encoding: .utf8) {
                text = formatted
            } else {
                text = current
            }
        case "/json":
            let snippet = """
            {
              "id": "{{request_id}}",
              "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
              "payload": {
                "status": "active"
              }
            }
            """
            text = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? snippet : current + snippet
        case "/graphql":
            let snippet = """
            {
              "query": "query GetViewer($first: Int!) { viewer { login repositories(first: $first) { nodes { name stargazerCount } } } }",
              "variables": {
                "first": 5
              }
            }
            """
            text = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? snippet : current + snippet
        case "/uuid":
            text = current + UUID().uuidString.lowercased()
        case "/iso8601":
            text = current + ISO8601DateFormatter().string(from: Date())
        case "/timestamp":
            text = current + "\(Int(Date().timeIntervalSince1970))"
        case "/op":
            text = current + "op://Private/API_Credential/token"
        case "/env":
            text = current + "{{base_url}}"
        case "/clear":
            text = ""
        default:
            text = current
        }
    }
}

struct VimTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var slashPrefix: String
    @Binding var slashSelectedIndex: Int
    var controller: VimModeController
    var language: CodeLanguage
    var enableSlashCommands: Bool
    var enableVimEditor: Bool
    var enableSyntaxHighlighting: Bool
    var onExecuteSlash: (SlashCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = CodeColors.nsBackground

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = VimHostTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.vimController = controller
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = CodeColors.nsBackground
        textView.insertionPointColor = .white
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.disableAutoFillFeatures()
        textView.string = text
        context.coordinator.applyHighlighting(to: textView)
        textView.updateExclusionPaths()

        scrollView.documentView = textView
        controller.activeTextView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? VimHostTextView else { return }
        textView.vimController = controller
        textView.coordinator = context.coordinator
        textView.updateExclusionPaths()

        let textChanged = textView.string != text
        let highlightToggleChanged = context.coordinator.lastHighlightEnabled != enableSyntaxHighlighting || context.coordinator.lastLanguage != language

        if textChanged && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            let maxLen = (textView.string as NSString).length
            let clampedRanges = selectedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                guard r.location <= maxLen else { return nil }
                return NSValue(range: NSRange(location: r.location, length: min(r.length, maxLen - r.location)))
            }
            if !clampedRanges.isEmpty {
                textView.selectedRanges = clampedRanges
            }
            context.coordinator.isUpdating = false
        } else if highlightToggleChanged && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            context.coordinator.applyHighlighting(to: textView)
            context.coordinator.isUpdating = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VimTextViewRepresentable
        var isUpdating = false
        var lastHighlightEnabled: Bool = true
        var lastLanguage: CodeLanguage = .json

        init(_ parent: VimTextViewRepresentable) {
            self.parent = parent
            self.lastHighlightEnabled = parent.enableSyntaxHighlighting
            self.lastLanguage = parent.language
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selected = textView.selectedRanges
            storage.beginEditing()
            switch parent.language {
            case .json, .raw:
                JSONHighlighter.apply(to: storage, enabled: parent.enableSyntaxHighlighting)
            case .bash:
                BashHighlighter.apply(to: storage, enabled: parent.enableSyntaxHighlighting)
            }
            storage.endEditing()
            textView.selectedRanges = selected
            textView.insertionPointColor = .white
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            lastHighlightEnabled = parent.enableSyntaxHighlighting
            lastLanguage = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            isUpdating = true
            let newText = tv.string
            parent.text = newText
            applyHighlighting(to: tv)
            if parent.enableSlashCommands {
                detectSlashPrefix(in: newText, cursorLocation: tv.selectedRange().location)
            } else if !parent.slashPrefix.isEmpty {
                parent.slashPrefix = ""
                parent.slashSelectedIndex = 0
            }
            isUpdating = false
        }

        private func detectSlashPrefix(in text: String, cursorLocation: Int) {
            let nsString = text as NSString
            let safeLoc = min(max(0, cursorLocation), nsString.length)
            let prefixText = nsString.substring(to: safeLoc)
            let lines = prefixText.components(separatedBy: .newlines)
            guard let currentLine = lines.last else {
                parent.slashPrefix = ""
                parent.slashSelectedIndex = 0
                return
            }

            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/") && !trimmed.contains(" ") {
                if parent.slashPrefix != trimmed {
                    parent.slashPrefix = trimmed
                    parent.slashSelectedIndex = 0
                }
            } else {
                parent.slashPrefix = ""
                parent.slashSelectedIndex = 0
            }
        }
    }
}

final class VimHostTextView: NSTextView {
    weak var vimController: VimModeController?
    weak var coordinator: VimTextViewRepresentable.Coordinator?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateExclusionPaths()
    }

    override func layout() {
        super.layout()
        updateExclusionPaths()
    }

    override func didChangeText() {
        super.didChangeText()
        updateExclusionPaths()
    }

    /// Dynamically excludes the top-right VimModeBadge region (`VIM:N` / `VIM:I` + `×` + `?`)
    /// from `textContainer` when Vim is active so the first line wraps early and never collides
    /// with the mode badge, recalculating automatically whenever the field size changes.
    func updateExclusionPaths() {
        guard let textContainer = self.textContainer else { return }
        let isVimActive = (vimController?.isVimActive == true)
        if isVimActive {
            let width = bounds.width > 0 ? bounds.width : textContainer.containerSize.width
            let badgeWidth: CGFloat = 115.0
            let lineHeight = layoutManager?.defaultLineHeight(
                for: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ) ?? 15.0
            let badgeHeight = max(10.0, lineHeight - 2.0)

            if width > badgeWidth + 40 {
                let exclusionRect = NSRect(
                    x: width - badgeWidth - textContainerInset.width,
                    y: 0,
                    width: badgeWidth + textContainerInset.width,
                    height: badgeHeight
                )
                if textContainer.exclusionPaths.first?.bounds != exclusionRect {
                    textContainer.exclusionPaths = [NSBezierPath(rect: exclusionRect)]
                }
            } else if !textContainer.exclusionPaths.isEmpty {
                textContainer.exclusionPaths = []
            }
        } else if !textContainer.exclusionPaths.isEmpty {
            textContainer.exclusionPaths = []
        }
    }

    func disableAutoFillFeatures() {
        isAutomaticTextCompletionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false

        if #available(macOS 14.0, *) {
            inlinePredictionType = .no
        }
        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none
            allowedWritingToolsResultOptions = []
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        disableAutoFillFeatures()
        vimController?.activeTextView = self
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Intercept slash command navigation and completion when slash suggestion bar is active
        if let coord = coordinator,
           coord.parent.enableSlashCommands,
           !coord.parent.slashPrefix.isEmpty {
            let matches = SlashCommand.match(
                for: coord.parent.slashPrefix,
                vimEnabled: coord.parent.enableVimEditor
            )
            if !matches.isEmpty {
                let isShift = event.modifierFlags.contains(.shift)
                switch event.keyCode {
                case 48: // Tab (or Shift-Tab)
                    if matches.count == 1 && !isShift {
                        coord.parent.onExecuteSlash(matches[0])
                    } else if isShift {
                        coord.parent.slashSelectedIndex = (coord.parent.slashSelectedIndex - 1 + matches.count) % matches.count
                    } else {
                        coord.parent.slashSelectedIndex = (coord.parent.slashSelectedIndex + 1) % matches.count
                    }
                    return
                case 125: // Down Arrow
                    coord.parent.slashSelectedIndex = (coord.parent.slashSelectedIndex + 1) % matches.count
                    return
                case 126: // Up Arrow
                    coord.parent.slashSelectedIndex = (coord.parent.slashSelectedIndex - 1 + matches.count) % matches.count
                    return
                case 36, 49: // Return or Space commits highlighted command
                    let idx = min(max(0, coord.parent.slashSelectedIndex), matches.count - 1)
                    coord.parent.onExecuteSlash(matches[idx])
                    return
                case 53: // Escape dismisses slash bar without mutating text
                    coord.parent.slashPrefix = ""
                    coord.parent.slashSelectedIndex = 0
                    return
                default:
                    break
                }
            }
        }

        // VimEngine v2.1.0 key forwarding
        if let vim = vimController?.engine {
            let prevSubmode = vim.submode
            let handled = vim.handleKey(
                chars: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: KeyModifiers(event.modifierFlags),
                editor: self
            )
            if handled {
                if prevSubmode != vim.submode {
                    needsDisplay = true
                }
                return
            }
        }

        super.keyDown(with: event)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if vimController?.engine != nil {
            if !stillSelecting, let primary = ranges.first?.rangeValue {
                scrollRangeToVisible(NSRange(location: primary.location, length: 0))
            }
            needsDisplay = true
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard flag else { return }
        if let vim = vimController?.engine, vim.submode != .insert {
            let charWidth: CGFloat = 8.0
            let blockRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: charWidth, height: rect.height)
            NSColor.systemPurple.withAlphaComponent(0.55).setFill()
            blockRect.fill(using: .sourceOver)
        } else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        }
    }
}
