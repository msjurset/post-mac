import AppKit
import Quartz
import SwiftUI

@MainActor
private let sharedNoAutoFillFieldEditor: NSTextView = {
    let editor = NSTextView()
    editor.isFieldEditor = true
    configureNoAutoFill(editor)
    return editor
}()

@MainActor
private func configureNoAutoFill(_ editor: NSTextView) {
    if editor.isAutomaticTextCompletionEnabled { editor.isAutomaticTextCompletionEnabled = false }
    if editor.isAutomaticSpellingCorrectionEnabled { editor.isAutomaticSpellingCorrectionEnabled = false }
    if editor.isAutomaticTextReplacementEnabled { editor.isAutomaticTextReplacementEnabled = false }
    if editor.isContinuousSpellCheckingEnabled { editor.isContinuousSpellCheckingEnabled = false }
    if editor.isAutomaticQuoteSubstitutionEnabled { editor.isAutomaticQuoteSubstitutionEnabled = false }
    if editor.isAutomaticDashSubstitutionEnabled { editor.isAutomaticDashSubstitutionEnabled = false }
    if editor.isAutomaticDataDetectionEnabled { editor.isAutomaticDataDetectionEnabled = false }
    if editor.isAutomaticLinkDetectionEnabled { editor.isAutomaticLinkDetectionEnabled = false }
    if #available(macOS 14.0, *) {
        if editor.inlinePredictionType != .no {
            editor.inlinePredictionType = .no
        }
    }
    if #available(macOS 15.0, *) {
        if editor.writingToolsBehavior != .none {
            editor.writingToolsBehavior = .none
        }
        if editor.allowedWritingToolsResultOptions != [] {
            editor.allowedWritingToolsResultOptions = []
        }
    }
}

final class FieldEditorInterceptor: NSObject, NSWindowDelegate {
    weak var wrapped: NSObject?

    init(wrapping wrapped: NSObject?) {
        self.wrapped = wrapped
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return wrapped?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let wrapped, wrapped.responds(to: aSelector) else { return nil }
        return wrapped
    }

    @MainActor
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        NSView.swizzleFocusRingTypeOnce()
        
        if client is NSTextField || client is NSTextFieldCell {
            return sharedNoAutoFillFieldEditor
        }
        
        if let original = wrapped, original.responds(to: #selector(windowWillReturnFieldEditor(_:to:))) {
            return original.perform(#selector(windowWillReturnFieldEditor(_:to:)), with: sender, with: client)?.takeUnretainedValue()
        }
        
        return nil
    }
}

@MainActor
private var installedInterceptors: [ObjectIdentifier: FieldEditorInterceptor] = [:]

@MainActor
private let predictivePanelFragments: [String] = [
    "InlinePrediction",
    "InlineSuggestion",
    "PredictionPanel",
    "WritingTools",
    "TextCompletion",
    "SPRoundedWindow",
]

@MainActor
private let reaperLogPath: String = {
    let path = NSHomeDirectory() + "/.post/reaper.log"
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? "".write(toFile: path, atomically: true, encoding: .utf8)
    return path
}()

@MainActor
private func reapLog(_ s: String) {
    let line = s + "\n"
    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: reaperLogPath)) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
    } else {
        try? line.write(toFile: reaperLogPath, atomically: true, encoding: .utf8)
    }
}

@MainActor
func reapPredictivePanels() {
    for window in NSApp.windows where window.isVisible {
        let name = NSStringFromClass(type(of: window))
        if predictivePanelFragments.contains(where: { name.contains($0) }) {
            reapLog("[reaper] KILLED \(name) frame=\(window.frame)")
            window.orderOut(nil)
        }
    }
}

@MainActor
func installFieldEditorInterceptor(on window: NSWindow) {
    let key = ObjectIdentifier(window)
    let currentDelegate = window.delegate as? NSObject
    if let existing = installedInterceptors[key],
       window.delegate === existing {
        return
    }
    let interceptor = FieldEditorInterceptor(wrapping: currentDelegate)
    installedInterceptors[key] = interceptor
    window.delegate = interceptor
}

extension NSWindow {
    func dropFocus() {
        self.makeFirstResponder(nil)
    }
}

@MainActor
private var hasSwizzledFocusRingType = false

extension NSView {
    @MainActor
    static func swizzleFocusRingTypeOnce() {
        guard !hasSwizzledFocusRingType else { return }
        hasSwizzledFocusRingType = true
        
        let originalSelector = #selector(getter: NSView.focusRingType)
        let swizzledSelector = #selector(getter: NSView.swizzled_focusRingType)
        
        guard let originalMethod = class_getInstanceMethod(NSView.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSView.self, swizzledSelector) else {
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    @objc var swizzled_focusRingType: NSFocusRingType {
        if self is NSTextField || self is NSTextView || self.className.contains("FieldEditor") {
            return self.swizzled_focusRingType
        }
        return .none
    }
}

final class PostAppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    @MainActor var urlHandler: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            urlHandler?(url)
        }
    }

    override init() {
        let prefs = UserDefaults.standard
        for key in [
            "NSAutomaticTextCompletionEnabled",
            "NSAutomaticInlinePredictionEnabled",
            "WebAutomaticTextReplacementEnabled",
            "NSAllowsCharacterPickerTouchBarItem",
            "NSAutomaticSpellingCorrectionEnabled",
            "NSAutomaticTextReplacementEnabled",
            "NSAutomaticQuoteSubstitutionEnabled",
            "NSAutomaticDashSubstitutionEnabled",
            "NSAutomaticDataDetectionEnabled",
            "NSAutomaticLinkDetectionEnabled",
        ] {
            prefs.set(false, forKey: key)
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            installFieldEditorInterceptor(on: window)
        }

        let didToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                installFieldEditorInterceptor(on: window)
            }
        }
        observers.append(didToken)

        let updateToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                installFieldEditorInterceptor(on: window)
            }
        }
        observers.append(updateToken)

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { event in
            MainActor.assumeIsolated {
                for window in NSApp.windows {
                    installFieldEditorInterceptor(on: window)
                }
                reapPredictivePanels()
                for delay in [0.05, 0.15, 0.35, 0.7] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        reapPredictivePanels()
                    }
                }
            }
            return event
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            installFieldEditorInterceptor(on: window)
        }
        if let panel = QLPreviewPanel.shared() {
            installFieldEditorInterceptor(on: panel)
        }
        reapPredictivePanels()
        for delay in [0.05, 0.15, 0.3, 0.6, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                reapPredictivePanels()
            }
        }
        let occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                reapPredictivePanels()
            }
        }
        observers.append(occlusionToken)
        let keyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                reapPredictivePanels()
            }
        }
        observers.append(keyToken)
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
