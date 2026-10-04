import Foundation

public struct DailyTask: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

public struct RoutineState: Codable, Equatable {
    public var tasks: [DailyTask]
    public var completedIDs: Set<UUID>
    public var cycleKey: String
    public var resetHour: Int
    public var resetMinute: Int
    public var isEnabled: Bool

    public init(
        tasks: [DailyTask] = [],
        completedIDs: Set<UUID> = [],
        cycleKey: String? = nil,
        resetHour: Int = 0,
        resetMinute: Int = 0,
        isEnabled: Bool = false
    ) {
        self.tasks = tasks
        self.completedIDs = completedIDs
        self.resetHour = resetHour
        self.resetMinute = resetMinute
        self.isEnabled = isEnabled
        self.cycleKey = cycleKey ?? Self.cycleKey(
            at: Date(), resetHour: resetHour, resetMinute: resetMinute, calendar: .current
        )
    }

    public var pendingTasks: [DailyTask] {
        tasks.filter { !completedIDs.contains($0.id) }
    }

    /// An empty routine is complete, so it never creates an input barrier.
    public var isComplete: Bool { pendingTasks.isEmpty }

    public mutating func completeTask(id: UUID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        completedIDs.insert(id)
    }

    /// Advance only. A clock adjustment or timezone change into an earlier cycle
    /// must not erase completed work or allow the same day to reset twice.
    @discardableResult
    public mutating func reconcile(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let nextKey = Self.cycleKey(
            at: date, resetHour: resetHour, resetMinute: resetMinute, calendar: calendar
        )
        guard nextKey > cycleKey else { return false }
        cycleKey = nextKey
        completedIDs.removeAll()
        return true
    }

    /// The cycle is identified by the Gregorian date of its local day boundary.
    /// A nonexistent DST reset time advances to the next valid time; an ambiguous
    /// repeated time uses its first occurrence. No fixed 24-hour arithmetic is used.
    public static func cycleKey(
        at date: Date,
        resetHour: Int,
        resetMinute: Int,
        calendar: Calendar
    ) -> String {
        let dayStart = calendar.startOfDay(for: date)
        // In-memory invalid settings cannot crash the app. The repository rejects
        // them before saving or returning a decoded state.
        let hour = min(23, max(0, resetHour))
        let minute = min(59, max(0, resetMinute))
        let reset = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? dayStart
        let cycleDay = date < reset
            ? (calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart)
            : dayStart
        var keyCalendar = Calendar(identifier: .gregorian)
        keyCalendar.timeZone = calendar.timeZone
        let parts = keyCalendar.dateComponents([.year, .month, .day], from: cycleDay)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
