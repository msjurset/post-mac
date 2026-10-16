import SwiftUI

@main
struct PostApp: App {
    @NSApplicationDelegateAdaptor(PostAppDelegate.self) var appDelegate
    @StateObject private var store = PostStore.live()

    var body: some Scene {
        WindowGroup {
            MainContentView(store: store)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Request") {
                    store.activeTab = .requests
                    store.createNewRequest()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Environments & Collections...") {
                    store.showingEnvironmentSheet = true
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Editor Settings...") {
                    store.showingSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Request") {
                Button("Execute Current Request") {
                    NotificationCenter.default.post(name: Notification.Name("ExecuteCurrentRequest"), object: nil)
                    Task {
                        await store.executeSelectedRequest()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.isExecuting || store.selectedRequest == nil)

                Divider()

                Button("Focus Search") {
                    store.focusSearchTrigger += 1
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Find in Requests") {
                    store.focusSearchTrigger += 1
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Reset / Load Sample Use Cases") {
                    store.resetToSampleData()
                }
            }
        }
    }
}
