import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(state)
                .frame(width: 380)
        } label: {
            Image(systemName: "key.horizontal.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
