import AppKit
import SwiftUI
import TaskLockCore

private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {}
    override func performClose(_ sender: Any?) {}
}

final class BarrierController {
    let store: AppStore
    let input = InputGate()
    private(set) var isLocked = false
    private var windows: [NSWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var previousPresentation: NSApplication.PresentationOptions = []
    private var sleeping = false
    private var systemLocked = false
    private var smokeDeadline: Date?
    private var smokePhase = 0
    private var smokeEvidence: [String: Any] = [:]
    private var previewStartedAt: Date?
    private var previewUsedInputGate = false

    init(store: AppStore) {
        self.store = store
        store.updateInputRegion = { [weak self] id, rect in self?.input.allowedRects[id] = rect }
    }

    func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.suspend() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.suspend() }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.wake() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.wake() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.suspend() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.wake() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self, self.isLocked else { return }
            self.makeWindows()
            self.reassert()
        }
        observe(.default, NSApplication.didResignActiveNotification) { [weak self] in
            guard let self, self.isLocked else { return }
            self.input.pointerAllowed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.reassert() }
        }
        observe(.default, NSApplication.didBecomeActiveNotification) { [weak self] in self?.input.pointerAllowed = true }
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.systemLocked = locked
                if locked { self.suspend() } else { self.wake() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
    }

    // Read-only defensive check supplements wake/unlock notifications. Never interfere with loginwindow.
    private var secureSessionVisible: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return systemLocked || (session?["CGSSessionScreenIsLocked"] as? Bool == true)
            || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
    }

    private func suspend() {
        sleeping = true
        input.stop()
        if isLocked { NSApp.presentationOptions = previousPresentation }
        if store.previewRemaining > 0 { stop(showSettings: false) }
    }

    private func wake() {
        sleeping = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.reconcile() }
    }

    private func tick() {
        store.refreshPermissions()
        if store.previewRemaining > 0 {
            store.previewRemaining -= 1
            if store.previewRemaining == 0 { stop(); return }
        }
        if let deadline = smokeDeadline { smokeTick(deadline: deadline) }
        reconcile()
    }

    func reconcile() {
        guard !sleeping, !secureSessionVisible else {
            if input.active { input.stop(); NSApp.presentationOptions = previousPresentation }
            return
        }
        store.reconcileDay()
        if store.previewRemaining > 0 {
            if !store.previewTasks.isEmpty && store.previewCompleted.count == store.previewTasks.count { stop() }
            return
        }
        guard store.shouldLock else { if isLocked { stop() }; return }
        guard store.accessibilityGranted else {
            if isLocked { stop() }
            store.errorMessage = "القفل غير مفعّل: يحتاج TaskLock إذن Accessibility."
            return
        }
        if !isLocked { start(strict: true) }
        else if !input.active {
            if input.start() { applyPresentation(); reassert() } else { failGate() }
        } else if !input.verify() { failGate() }
        else if !NSApp.isActive { reassert() }
    }

    private func failGate() {
        stop()
        store.errorMessage = "توقف حجب الإدخال. راجع إذن Accessibility؛ المهام محفوظة."
        store.showSettings?()
    }

    private func start(strict: Bool) {
        guard !isLocked else { return }
        if strict && !input.start() {
            store.errorMessage = "لم يتم تشغيل حجب الكيبورد. فعّل TaskLock في Accessibility ثم أعد فتح التطبيق."
            return
        }
        previousPresentation = NSApp.presentationOptions
        isLocked = true
        store.isLocked = true
        for window in NSApp.windows where window.isVisible { window.orderOut(nil) }
        makeWindows()
        applyPresentation()
        reassert()
    }

    private func applyPresentation() {
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableAppleMenu, .disableProcessSwitching, .disableForceQuit, .disableHideApplication]
    }

    private func makeWindows() {
        input.allowedRects = [:]
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        for screen in NSScreen.screens {
            let window = ShieldWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: false)
            window.title = "TaskLock — مهام اليوم"
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.052, blue: 0.067, alpha: 1)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LockView(store: store).environment(\.layoutDirection, .rightToLeft))
            windows.append(window)
        }
    }

    func reassert() {
        guard isLocked, !sleeping, !secureSessionVisible else { return }
        applyPresentation()
        for window in windows { window.orderFrontRegardless() }
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        input.pointerAllowed = NSApp.isActive
    }

    func stop(showSettings: Bool = true) {
        let hadInputGate = input.active
        input.stop()
        guard isLocked else { return }
        isLocked = false
        store.isLocked = false
        store.previewRemaining = 0
        NSApp.presentationOptions = previousPresentation
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        input.allowedRects = [:]
        if let started = previewStartedAt {
            let evidence: [String: Any] = [
                "startedAt": ISO8601DateFormatter().string(from: started),
                "endedAt": ISO8601DateFormatter().string(from: Date()),
                "inputGateStarted": previewUsedInputGate,
                "inputGateActiveAtEnd": hadInputGate,
                "blockedEvents": input.blockedEvents,
                "blockedKeyboardEvents": input.blockedKeyboardEvents,
                "acceptedClicks": input.acceptedClicks,
                "completedPreviewTasks": store.previewCompleted.count,
                "previewTaskCount": store.previewTasks.count,
                "inputReleased": !input.active,
                "presentationRestored": NSApp.presentationOptions == previousPresentation,
                "displayCount": NSScreen.screens.count,
                "realRoutineModified": false
            ]
            let url = store.repository.url.deletingLastPathComponent().appendingPathComponent("preview-evidence.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
            previewStartedAt = nil
        }
        if showSettings && smokeDeadline == nil { store.showSettings?() }
    }

    func startPreview() {
        guard !isLocked else { return }
        store.previewTasks = [DailyTask(title: "شربت كوب مياه"), DailyTask(title: "خلصت التمرين"), DailyTask(title: "قرأت ١٠ دقائق")]
        store.previewCompleted = []
        store.previewRemaining = 15
        start(strict: store.accessibilityGranted)
        if isLocked { previewStartedAt = Date(); previewUsedInputGate = input.active }
    }

    // Only the separately identified .test app can execute the bounded smoke harness.
    func runSmokeTest() {
        guard store.testMode else { return }
        smokeEvidence = ["startedAt": ISO8601DateFormatter().string(from: Date()), "accessibility": store.accessibilityGranted]
        smokeDeadline = Date().addingTimeInterval(20)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startPreview() }
    }

    func runStorageFailureTest() {
        guard store.testMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let task = DailyTask(title: "Storage failure test only")
            let testState = RoutineState(tasks: [task], isEnabled: true)
            let parent = self.store.repository.url.deletingLastPathComponent()
            var evidence: [String: Any] = [:]
            do {
                var invalid = testState
                invalid.tasks[0].title = ""
                evidence["validationRejectedWithoutStorageLatch"] = !self.store.persist(invalid) && self.store.storageHealthy
                guard self.store.persist(testState) else { throw CocoaError(.fileWriteUnknown) }
                let before = try Data(contentsOf: self.store.repository.url)
                self.start(strict: self.store.accessibilityGranted)
                evidence["inputWasActive"] = self.input.active
                evidence["barrierWasActive"] = self.isLocked
                evidence["kioskWasActive"] = NSApp.presentationOptions.contains(.disableProcessSwitching)
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
                self.store.complete(task.id)
                evidence["storageFailureLatched"] = !self.store.storageHealthy
                evidence["barrierReleased"] = !self.isLocked
                evidence["inputReleased"] = !self.input.active
                evidence["presentationRestored"] = NSApp.presentationOptions == self.previousPresentation
                evidence["failedCompletionNotRecorded"] = !self.store.state.completedIDs.contains(task.id)
                evidence["originalBytesPreserved"] = (try Data(contentsOf: self.store.repository.url)) == before
                evidence["errorVisible"] = self.store.errorMessage != nil
            } catch { evidence["testError"] = error.localizedDescription }
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            self.stop(showSettings: false)
            let output = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TaskLock-Testing/storage-failure-evidence.json")
            try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output, options: .atomic) }
            try? FileManager.default.removeItem(at: parent)
            NSApp.terminate(nil)
        }
    }

    private func smokeTick(deadline: Date) {
        let elapsed = 20 - deadline.timeIntervalSinceNow
        if elapsed >= 4 && smokePhase == 0 {
            smokeEvidence["shieldCount"] = windows.count
            smokeEvidence["displayCount"] = NSScreen.screens.count
            smokeEvidence["locked"] = isLocked
            smokeEvidence["inputGateActive"] = input.active
            smokeEvidence["presentationOptions"] = NSApp.presentationOptions.rawValue
            smokeEvidence["frontmost"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            if let view = windows.first?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let url = store.repository.url.deletingLastPathComponent().appendingPathComponent("preview.png")
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
            }
            smokePhase = 1
        }
        if elapsed >= 11 && smokePhase == 1 {
            smokeEvidence["blockedEvents"] = input.blockedEvents
            for task in store.previewTasks { store.complete(task.id) }
            smokeEvidence["completionUnlocked"] = !isLocked
            smokeEvidence["inputReleased"] = !input.active
            smokeEvidence["presentationRestored"] = NSApp.presentationOptions == previousPresentation
            smokePhase = 2
        }
        if elapsed >= 13 && smokePhase == 2 {
            smokeEvidence["endedAt"] = ISO8601DateFormatter().string(from: Date())
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TaskLock-Testing/smoke-evidence.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: smokeEvidence, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
            smokeDeadline = nil
            stop()
            NSApp.terminate(nil)
        }
    }
}
