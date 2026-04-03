import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "Pi"
            button.toolTip = "Pi Island"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Pi Island", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Pi Island",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        menu.items.last?.target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct PiIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    private let server: EventServer?

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        let server = EventServer(model: model)
        server?.start()
        self.server = server
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
