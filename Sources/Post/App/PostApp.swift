import SwiftUI

@main
struct PostApp: App {
    @NSApplicationDelegateAdaptor(PostAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
