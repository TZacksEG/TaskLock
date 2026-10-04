import AppKit
import SwiftUI
import ApplicationServices
import ServiceManagement
import TaskLockCore

final class AppStore: ObservableObject {
    @Published private(set) var state: RoutineState
    @Published var accessibilityGranted = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var isLocked = false
    @Published var errorMessage: String?
    @Published var storageHealthy = true
    @Published var previewRemaining = 0
    @Published var previewTasks: [DailyTask] = []
    @Published var previewCompleted: Set<UUID> = []
    @Published var configurationRevision = 0
    let repository: RoutineRepository
    let testMode: Bool
    var onChange: (() -> Void)?
    var showSettings: (() -> Void)?
    var preview: (() -> Void)?
    var updateInputRegion: ((Int, CGRect) -> Void)?

    init(testMode: Bool, testRepositoryURL: URL? = nil) {
        self.testMode = testMode
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = testMode ? "TaskLock-Testing" : (Bundle.main.bundleIdentifier == "app.tasklock.desktop" ? "TaskLock-Desktop" : "TaskLock")
        let url = (testMode ? testRepositoryURL : nil) ?? base.appendingPathComponent(folder).appendingPathComponent("routine.json")
        repository = RoutineRepository(url: url)
        do { state = try repository.load() }
        catch {
            state = RoutineState()
            storageHealthy = false
            errorMessage = "تعذّر قراءة المهام المحفوظة. لم يتم تغيير الملف الأصلي. \(error.localizedDescription)"
        }
        refreshPermissions()
    }

    var tasks: [DailyTask] { previewRemaining > 0 ? previewTasks : state.tasks }
    var completed: Set<UUID> { previewRemaining > 0 ? previewCompleted : state.completedIDs }
    var completedCount: Int { tasks.filter { completed.contains($0.id) }.count }
    var shouldLock: Bool { storageHealthy && state.isEnabled && !state.tasks.isEmpty && !state.isComplete }

    func persist(_ candidate: RoutineState) -> Bool {
        guard storageHealthy else { return false }
        do {
            try repository.save(candidate)
            state = candidate
            errorMessage = nil
            return true
        } catch let error as RoutineValidationError {
            errorMessage = "راجع المهام والإعدادات: \(error.localizedDescription)"
            return false
        } catch {
            storageHealthy = false
            errorMessage = "تعذّر حفظ التقدم، لذلك لم يتم تسجيل التغيير: \(error.localizedDescription)"
            onChange?()
            return false
        }
    }

    func retryStorage() {
        guard !isLocked else { return }
        do {
            let loaded = try repository.load()
            try repository.save(loaded)
            state = loaded
            configurationRevision += 1
            storageHealthy = true
            errorMessage = nil
            onChange?()
        } catch { errorMessage = "ما زال ملف المهام غير متاح: \(error.localizedDescription)" }
    }

    func reconcileDay() {
        var next = state
        if next.reconcile() { _ = persist(next) }
    }

    func complete(_ id: UUID) {
        if previewRemaining > 0 {
            previewCompleted.insert(id)
            onChange?()
            return
        }
        var next = state
        _ = next.reconcile()
        next.completeTask(id: id)
        if persist(next) { onChange?() }
    }

    func saveRoutine(tasks: [DailyTask], hour: Int, minute: Int) {
        guard accessibilityGranted else {
            errorMessage = "فعّل إذن Accessibility أولًا، ثم اضغط حفظ وتفعيل."
            return
        }
        var next = state
        next.tasks = tasks.map { DailyTask(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let unchangedIDs = Set(next.tasks.filter { task in state.tasks.contains { $0.id == task.id && $0.title == task.title } }.map(\.id))
        next.completedIDs = next.completedIDs.intersection(unchangedIDs)
        next.resetHour = hour
        next.resetMinute = minute
        next.cycleKey = RoutineState.cycleKey(at: Date(), resetHour: hour, resetMinute: minute, calendar: .current)
        next.isEnabled = true
        guard !next.tasks.isEmpty else { errorMessage = "أضف مهمة واحدة على الأقل."; return }
        if persist(next) { onChange?() }
    }

    func disableRoutine() {
        guard !isLocked else { return }
        var next = state
        next.isEnabled = false
        if persist(next) { onChange?() }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    func configureLoginOnFirstRun() {
        guard !testMode, Bundle.main.bundleURL.path == "/Applications/TaskLock.app" else { return }
        // Shared builds ask each recipient to opt in using the visible startup switch.
        guard Bundle.main.bundleIdentifier == "local.tamer.TaskLock" else { return }
        guard !UserDefaults.standard.bool(forKey: "loginSetupAttempted") else { return }
        setLoginEnabled(true)
        if loginEnabled || loginNeedsApproval { UserDefaults.standard.set(true, forKey: "loginSetupAttempted") }
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard !testMode else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = "تعذّر ضبط التشغيل التلقائي: \(error.localizedDescription)" }
        refreshPermissions()
    }
}
