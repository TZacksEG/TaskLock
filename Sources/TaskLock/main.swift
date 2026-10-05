import AppKit
import SwiftUI
import ServiceManagement
import Carbon

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// TaskLock is a menu-bar agent. Closing its settings window must leave the
// daily routine running without occupying the Dock.
application.setActivationPolicy(.accessory)
application.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore!
    var barrier: BarrierController!
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    let testMode = Bundle.main.bundleIdentifier?.hasSuffix(".test") == true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy must never compete for the same persisted routine.
        let ownIdentifier = Bundle.main.bundleIdentifier ?? "local.tamer.TaskLock"
        let identifiers = testMode ? [ownIdentifier] : Array(Set([ownIdentifier, "local.tamer.TaskLock", "app.tasklock.desktop"]))
        let peers = identifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        if let peer = peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            peer.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        let failureTest = testMode && CommandLine.arguments.contains("--storage-failure-test")
        let testURL = failureTest ? FileManager.default.temporaryDirectory.appendingPathComponent("TaskLock-Failure-\(UUID().uuidString)/routine.json") : nil
        store = AppStore(testMode: testMode, testRepositoryURL: testURL)
        barrier = BarrierController(store: store)
        store.onChange = { [weak self] in self?.barrier.reconcile() }
        store.showSettings = { [weak self] in self?.openSettings() }
        store.preview = { [weak self] in self?.barrier.startPreview() }
        setupMenu()
        if !testMode { store.configureLoginOnFirstRun() }
        barrier.observeLifecycle()
        barrier.reconcile()
        if !barrier.isLocked { openSettings() }
        if testMode && CommandLine.arguments.contains("--menu-bar-test") {
            runMenuBarTest()
        }
        if testMode && CommandLine.arguments.contains("--smoke-test") {
            barrier.runSmokeTest()
        }
        if failureTest { barrier.runStorageFailureTest() }
    }

    func setupMenu() {
        let main = NSMenu()
        let root = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "إعدادات TaskLock", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "إنهاء TaskLock", action: #selector(quit), keyEquivalent: "q").target = self
        root.submenu = app
        main.addItem(root)
        // Standard Edit commands are available only while editing the routine.
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editRoot.submenu = edit
        main.addItem(editRoot)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "TaskLock")
        statusItem?.button?.toolTip = "TaskLock — مهام اليوم"
        statusItem?.menu = app.copy() as? NSMenu
    }

    @objc func openSettings() {
        guard barrier?.isLocked != true else { return }
        store.refreshPermissions()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 740), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "TaskLock — روتينك اليومي"
            window.minSize = NSSize(width: 720, height: 660)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.09, alpha: 1)
            window.contentView = NSHostingView(rootView: SettingsView(store: store).environment(\.layoutDirection, .rightToLeft))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func runMenuBarTest() {
        guard testMode else { return }
        let output = store.repository.url.deletingLastPathComponent().appendingPathComponent("menu-bar-evidence.json")
        var evidence: [String: Any] = [
            "activationPolicyAccessory": NSApp.activationPolicy() == .accessory,
            "infoPlistAgent": (Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool) == true,
            "menuBarItemPresent": statusItem?.button != nil,
            "settingsOpenedAtLaunch": settingsWindow?.isVisible == true
        ]
        settingsWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            evidence["settingsHiddenAfterClose"] = self.settingsWindow?.isVisible == false
            evidence["processStillRunningAfterClose"] = NSApp.isRunning
            evidence["menuActionWired"] = self.statusItem?.menu?.items.first?.action == #selector(self.openSettings)
            if let menu = self.statusItem?.menu { menu.performActionForItem(at: 0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                evidence["settingsReopenedFromMenu"] = self.settingsWindow?.isVisible == true
                evidence["dockExcluded"] = (evidence["activationPolicyAccessory"] as? Bool == true)
                    && (evidence["infoPlistAgent"] as? Bool == true)
                try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: output, options: .atomic)
                }
                NSApp.terminate(nil)
            }
        }
    }

    @objc func quit() { if barrier?.isLocked != true { NSApp.terminate(nil) } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let reason = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue,
           [OSType(kAEQuitAll), OSType(kAEShutDown), OSType(kAERestart), OSType(kAEReallyLogOut), OSType(kAELogOut)].contains(reason) {
            barrier?.stop(showSettings: false)
            return .terminateNow
        }
        return barrier?.isLocked == true ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { barrier?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if barrier?.isLocked == true { barrier.reassert() } else { openSettings() }
        return false
    }
}
