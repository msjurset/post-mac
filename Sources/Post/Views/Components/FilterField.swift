import AppKit
import SwiftUI

/// A text field that suppresses macOS autofill/autocomplete popups.
/// Use this instead of SwiftUI TextField for every text input on macOS —
/// SwiftUI TextField shows a phantom autocomplete dropdown no modifier
/// can kill.
///
/// Internally this is a SwiftUI `ZStack` overlaying a SwiftUI `Text`
/// placeholder on top of an `NSViewRepresentable`-wrapped
/// `NoAutoFillTextField`. The NSTextField's own `placeholderString` is
/// kept empty so the cell never draws a placeholder — that draw path
/// has a known bug with the externally-supplied shared field editor
/// (layer 5 of the autofill suppression stack) where the cell's
/// `stringValue` stays empty during typing and the placeholder ghosts
/// under the typed text. Driving placeholder visibility from the
/// SwiftUI side via `text.isEmpty` sidesteps that entirely.
struct FilterField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (() -> Bool)?
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?
    var autoFocus: Bool = false
    var isDisabled: Bool = false
    /// Bumping this integer requests that the field become first responder.
    /// Use instead of SwiftUI @FocusState, which doesn't bind to NSViewRepresentable.
    var focusTrigger: Int = 0
    /// One-shot caret move request. When non-nil, the field positions its
    /// caret there and clears the binding so the request isn't applied
    /// twice. User-driven cursor moves never write to this binding —
    /// the source of truth for the live caret is the field editor itself.
    /// Used by suggestion-accept handlers to land the cursor at the end
    /// of the inserted text (e.g. after "is" → "is:" the cursor goes to
    /// 3, not 2, so the next keystroke types past the colon).
    @Binding var pendingCursor: Int?
    /// Visual style — .rounded for form/sheet inputs, .plain for inline search bars.
    var style: Style = .rounded
    var multiline: Bool = false
    var alignment: NSTextAlignment = .left
    var onSelectionChanged: ((Int) -> Void)? = nil
    var onFocusWithView: ((NSView) -> Void)? = nil
    var onUpArrow: (() -> Bool)? = nil
    var onDownArrow: (() -> Bool)? = nil
    var onTab: (() -> Bool)? = nil
    var onShiftTab: (() -> Bool)? = nil

    enum Style { case rounded, plain }

    init(placeholder: String,
         text: Binding<String>,
         onCommit: (() -> Void)? = nil,
         onFocus: (() -> Void)? = nil,
         onBlur: (() -> Void)? = nil,
         autoFocus: Bool = false,
         focusTrigger: Int = 0,
         pendingCursor: Binding<Int?> = .constant(nil),
         style: Style = .rounded,
         alignment: NSTextAlignment = .left,
         onSelectionChanged: ((Int) -> Void)? = nil,
         onFocusWithView: ((NSView) -> Void)? = nil,
         onUpArrow: (() -> Bool)? = nil,
         onDownArrow: (() -> Bool)? = nil,
         onTab: (() -> Bool)? = nil,
         onShiftTab: (() -> Bool)? = nil) {
        self.init(placeholder: placeholder, text: text, onCommit: onCommit != nil ? { onCommit!(); return true } : nil, onFocus: onFocus, onBlur: onBlur, autoFocus: autoFocus, focusTrigger: focusTrigger, pendingCursor: pendingCursor, style: style, alignment: alignment, onSelectionChanged: onSelectionChanged, onFocusWithView: onFocusWithView, onUpArrow: onUpArrow, onDownArrow: onDownArrow, onTab: onTab, onShiftTab: onShiftTab)
    }
    init(placeholder: String,
         text: Binding<String>,
         onCommit: (() -> Bool)? = nil,
         onFocus: (() -> Void)? = nil,
         onBlur: (() -> Void)? = nil,
         autoFocus: Bool = false,
         isDisabled: Bool = false,
         focusTrigger: Int = 0,
         pendingCursor: Binding<Int?> = .constant(nil),
         style: Style = .rounded,
         multiline: Bool = false,
         alignment: NSTextAlignment = .left,
         onSelectionChanged: ((Int) -> Void)? = nil,
         onFocusWithView: ((NSView) -> Void)? = nil,
         onUpArrow: (() -> Bool)? = nil,
         onDownArrow: (() -> Bool)? = nil,
         onTab: (() -> Bool)? = nil,
         onShiftTab: (() -> Bool)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onCommit = onCommit
        self.onFocus = onFocus
        self.onBlur = onBlur
        self.autoFocus = autoFocus
        self.isDisabled = isDisabled
        self.focusTrigger = focusTrigger
        self._pendingCursor = pendingCursor
        self.style = style
        self.multiline = multiline
        self.alignment = alignment
        self.onSelectionChanged = onSelectionChanged
        self.onFocusWithView = onFocusWithView
        self.onUpArrow = onUpArrow
        self.onDownArrow = onDownArrow
        self.onTab = onTab
        self.onShiftTab = onShiftTab
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, style == .rounded ? 6 : 0)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: alignment == .right ? .trailing : (alignment == .center ? .center : .leading))
            }
            FilterFieldRepresentable(
                text: $text,
                onCommit: onCommit,
                onFocus: onFocus,
                onBlur: onBlur,
                autoFocus: autoFocus,
                isDisabled: isDisabled,
                focusTrigger: focusTrigger,
                pendingCursor: $pendingCursor,
                style: style,
                multiline: multiline,
                alignment: alignment,
                onSelectionChanged: onSelectionChanged,
                onFocusWithView: onFocusWithView,
                onUpArrow: onUpArrow,
                onDownArrow: onDownArrow,
                onTab: onTab,
                onShiftTab: onShiftTab
            )
        }
    }
}

private struct FilterFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (() -> Bool)?
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?
    var autoFocus: Bool
    var isDisabled: Bool
    var focusTrigger: Int
    @Binding var pendingCursor: Int?
    var style: FilterField.Style
    var multiline: Bool
    var alignment: NSTextAlignment
    var onSelectionChanged: ((Int) -> Void)?
    var onFocusWithView: ((NSView) -> Void)?
    var onUpArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onShiftTab: (() -> Bool)?

    func makeNSView(context: Context) -> NoAutoFillTextField {
        let field = NoAutoFillTextField()
        
        let cell = NoAutoFillTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        field.cell = cell
        field.alignment = alignment
        
        field.onFocusReceived = onFocus
        field.onFocusWithView = onFocusWithView
        field.placeholderString = ""
        
        if multiline {
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
            field.lineBreakMode = .byWordWrapping
        } else {
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.cell?.usesSingleLineMode = true
        }
        
        switch style {
        case .rounded:
            field.bezelStyle = .roundedBezel
            field.isBordered = true
            field.drawsBackground = true
            field.focusRingType = .none
        case .plain:
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
        }
        field.delegate = context.coordinator
        field.isAutomaticTextCompletionEnabled = false
        field.contentType = .none
        context.coordinator.lastFocusTrigger = focusTrigger
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                field.window?.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NoAutoFillTextField, context: Context) {
        nsView.isEnabled = !isDisabled
        nsView.onFocusReceived = onFocus
        nsView.onFocusWithView = onFocusWithView
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onCommit = onCommit
        context.coordinator.onBlur = onBlur
        context.coordinator.onUpArrow = onUpArrow
        context.coordinator.onDownArrow = onDownArrow
        context.coordinator.onTab = onTab
        context.coordinator.onShiftTab = onShiftTab
        let editor = nsView.currentEditor() as? NSTextView
        if let editor, let storage = editor.textStorage {
            if storage.string != text {
                context.coordinator.isProgrammaticEdit = true
                storage.beginEditing()
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
                let fullRange = NSRange(location: 0, length: storage.length)
                if let textColor = nsView.textColor {
                    storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                }
                if let font = nsView.font {
                    storage.addAttribute(.font, value: font, range: fullRange)
                }
                storage.endEditing()
                DispatchQueue.main.async {
                    context.coordinator.isProgrammaticEdit = false
                }
            }
            if let cursor = pendingCursor {
                let target = cursor
                editor.selectedRange = NSRange(location: max(0, min(target, storage.length)), length: 0)
                DispatchQueue.main.async {
                    if let e = nsView.currentEditor() as? NSTextView,
                       let s = e.textStorage {
                        let clamped = max(0, min(target, s.length))
                        e.selectedRange = NSRange(location: clamped, length: 0)
                    }
                    self.pendingCursor = nil
                }
            }
        } else {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
            if pendingCursor != nil {
                DispatchQueue.main.async { self.pendingCursor = nil }
            }
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onBlur: onBlur, onSelectionChanged: onSelectionChanged, onUpArrow: onUpArrow, onDownArrow: onDownArrow, onTab: onTab, onShiftTab: onShiftTab)
    }

    class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var text: Binding<String>
        var onCommit: (() -> Bool)?
        var onBlur: (() -> Void)?
        var onSelectionChanged: ((Int) -> Void)?
        var lastFocusTrigger: Int = 0
        var onUpArrow: (() -> Bool)?
        var onDownArrow: (() -> Bool)?
        var onTab: (() -> Bool)?
        var onShiftTab: (() -> Bool)?
        var isProgrammaticEdit = false

        init(text: Binding<String>, onCommit: (() -> Bool)?, onBlur: (() -> Void)?, onSelectionChanged: ((Int) -> Void)?, onUpArrow: (() -> Bool)?, onDownArrow: (() -> Bool)?, onTab: (() -> Bool)?, onShiftTab: (() -> Bool)?) {
            self.text = text
            self.onCommit = onCommit
            self.onBlur = onBlur
            self.onSelectionChanged = onSelectionChanged
            self.onUpArrow = onUpArrow
            self.onDownArrow = onDownArrow
            self.onTab = onTab
            self.onShiftTab = onShiftTab
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isProgrammaticEdit else { return }
            guard let field = obj.object as? NSTextField else { return }
            let editor = (obj.userInfo?["NSFieldEditor"] as? NSText)
                ?? (field.currentEditor())
            let newText = editor?.string ?? field.stringValue
            text.wrappedValue = newText
            
            let location = editor?.selectedRange.location ?? newText.count
            onSelectionChanged?(location)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticEdit else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let location = textView.selectedRange.location
            onSelectionChanged?(location)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            onBlur?()
            if let userInfo = obj.userInfo,
               let movementInt = userInfo["NSTextMovement"] as? Int,
               movementInt == NSTextMovement.return.rawValue {
                _ = onCommit?()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                let range = textView.selectedRange()
                let lineRange = (textView.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
                if lineRange.location == 0 {
                    if let onUpArrow = onUpArrow, onUpArrow() {
                        return true
                    }
                }
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                let range = textView.selectedRange()
                let stringCount = textView.string.count
                let lineRange = (textView.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
                if NSMaxRange(lineRange) == stringCount || (lineRange.length == 0 && range.location == stringCount) {
                    if let onDownArrow = onDownArrow, onDownArrow() {
                        return true
                    }
                }
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                if !modifiers.contains(.shift) && !modifiers.contains(.option) {
                    if let onCommit = onCommit, onCommit() {
                        return true
                    }
                }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let onTab = onTab, onTab() { return true }
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let onShiftTab = onShiftTab, onShiftTab() { return true }
            }
            return false
        }
    }
}

final class NoAutoFillTextField: NSTextField, NSTextViewDelegate {
    override var allowsCharacterPickerTouchBarItem: Bool {
        get { false }
        set {}
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if let coordinator = delegate as? FilterFieldRepresentable.Coordinator {
            coordinator.textViewDidChangeSelection(notification)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            installFieldEditorInterceptor(on: window)
        }
    }

    var onFocusReceived: (() -> Void)?
    var onFocusWithView: ((NSView) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            disableAllAutoComplete(editor)
        }
        if result {
            onFocusReceived?()
            onFocusWithView?(self)
        }
        return result
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        if let editor = currentEditor() as? NSTextView {
            disableAllAutoComplete(editor)
        }
    }

    override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        if let editor = textObject as? NSTextView {
            disableAllAutoComplete(editor)
        }
        return super.textShouldBeginEditing(textObject)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers
            if key == "v" {
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            } else if key == "c" {
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            } else if key == "x" {
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            } else if key == "a" {
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            } else if key == "z" {
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            } else if key == "Z" && event.modifierFlags.contains(.shift) {
                if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override class var cellClass: AnyClass? {
        get { NoAutoFillTextFieldCell.self }
        set {}
    }

    fileprivate func disableAllAutoComplete(_ editor: NSTextView) {
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        if #available(macOS 14.0, *) {
            editor.inlinePredictionType = .no
        }
        if #available(macOS 15.0, *) {
            editor.writingToolsBehavior = .none
            editor.allowedWritingToolsResultOptions = []
        }
    }
}

final class NoAutoFillTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let configured = super.setUpFieldEditorAttributes(textObj)
        if let editor = configured as? NSTextView,
           let owner = controlView as? NoAutoFillTextField {
            owner.disableAllAutoComplete(editor)
        }
        return configured
    }
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var newRect = super.drawingRect(forBounds: rect)
        if wraps {
            let textSize = self.cellSize(forBounds: rect)
            newRect.size.height = min(rect.height, textSize.height)
        }
        return newRect
    }
}
