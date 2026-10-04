import Foundation

public enum RoutineValidationError: LocalizedError, Equatable {
    case invalidResetTime
    case invalidCycleKey
    case tooManyTasks
    case invalidTaskTitle
    case duplicateTaskID
    case unknownCompletedTask

    public var errorDescription: String? {
        switch self {
        case .invalidResetTime: return "The daily reset must be a valid hour and minute."
        case .invalidCycleKey: return "The saved daily cycle date is invalid."
        case .tooManyTasks: return "A daily routine can contain up to 100 tasks."
        case .invalidTaskTitle: return "Task names must contain between 1 and 240 characters."
        case .duplicateTaskID: return "The saved routine contains duplicate task identifiers."
        case .unknownCompletedTask: return "The saved routine contains a completion for an unknown task."
        }
    }
}

public struct RoutineRepository {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Missing files are a first launch. Malformed or invalid files are surfaced
    /// to the caller and left untouched; they are never silently replaced.
    public func load() throws -> RoutineState {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return RoutineState()
        }
        let state = try JSONDecoder().decode(RoutineState.self, from: data)
        try validate(state)
        return state
    }

    public func save(_ state: RoutineState) throws {
        try validate(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = parent.appendingPathComponent(".tasklock-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        defer { try? manager.removeItem(at: temporary) }
        // Write a private sibling first, then rename it into place. A write error
        // preserves the old file and a successful replacement retains mode 0600.
        try data.write(to: temporary)
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }

    private func validate(_ state: RoutineState) throws {
        guard (0...23).contains(state.resetHour), (0...59).contains(state.resetMinute) else {
            throw RoutineValidationError.invalidResetTime
        }
        guard Self.isValidCycleKey(state.cycleKey) else { throw RoutineValidationError.invalidCycleKey }
        guard state.tasks.count <= 100 else { throw RoutineValidationError.tooManyTasks }
        guard state.tasks.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 240
        }) else { throw RoutineValidationError.invalidTaskTitle }
        let ids = Set(state.tasks.map(\.id))
        guard ids.count == state.tasks.count else { throw RoutineValidationError.duplicateTaskID }
        guard state.completedIDs.isSubset(of: ids) else { throw RoutineValidationError.unknownCompletedTask }
    }

    private static func isValidCycleKey(_ key: String) -> Bool {
        guard key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            return false
        }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        return normalized.year == parts[0] && normalized.month == parts[1] && normalized.day == parts[2]
    }
}
