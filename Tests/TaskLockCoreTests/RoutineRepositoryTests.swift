import Foundation
import XCTest
@testable import TaskLockCore

final class RoutineRepositoryTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("routine.json") }
    private var repository: RoutineRepository { RoutineRepository(url: file) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TaskLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testMissingFileYieldsFreshEmptyDisabledStateWithoutWriting() throws {
        let state = try repository.load()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRestartPreservesPartialCompletionAndConfiguration() throws {
        let one = DailyTask(title: "Walk")
        let two = DailyTask(title: "Breakfast")
        let state = RoutineState(tasks: [one, two], completedIDs: [one.id], cycleKey: "2026-10-04", resetHour: 5, resetMinute: 30, isEnabled: true)
        try repository.save(state)
        let restarted = RoutineRepository(url: file)
        XCTAssertEqual(try restarted.load(), state)
        XCTAssertEqual(try restarted.load().pendingTasks, [two])
    }

    func testAtomicReplacementPreservesNewestStateAndOwnerOnlyPermissions() throws {
        let task = DailyTask(title: "Walk")
        var state = RoutineState(tasks: [task], cycleKey: "2026-10-04", isEnabled: true)
        try repository.save(state)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        state.completeTask(id: task.id)
        try repository.save(state)
        XCTAssertEqual(try repository.load(), state)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["routine.json"])
    }

    func testSaveCreatesMissingParentDirectory() throws {
        let nested = directory.appendingPathComponent("nested/routine.json")
        let repo = RoutineRepository(url: nested)
        let state = RoutineState()
        try repo.save(state)
        XCTAssertEqual(try repo.load(), state)
    }

    func testCorruptFileThrowsAndPreservesOriginalBytes() throws {
        let data = Data("broken { json".utf8)
        try data.write(to: file)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testDecodeInvalidStateThrowsAndPreservesOriginalBytes() throws {
        let state = RoutineState(resetHour: 24)
        let data = try JSONEncoder().encode(state)
        try data.write(to: file)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testInvalidSaveDoesNotOverwriteLastValidState() throws {
        let valid = RoutineState(tasks: [DailyTask(title: "Walk")])
        try repository.save(valid)
        let before = try Data(contentsOf: file)
        var invalid = valid
        invalid.resetMinute = 60
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testValidationRejectsInvalidTitlesCountsIDsDatesAndTimes() throws {
        let task = DailyTask(title: "Walk")
        let cases: [RoutineState] = [
            RoutineState(tasks: [DailyTask(title: " \n\t ")]),
            RoutineState(tasks: [DailyTask(title: String(repeating: "x", count: 241))]),
            RoutineState(tasks: (0..<101).map { DailyTask(title: "Task \($0)") }),
            RoutineState(tasks: [task, task]),
            RoutineState(tasks: [task], completedIDs: [UUID()]),
            RoutineState(cycleKey: "bad"),
            RoutineState(cycleKey: "2026-02-30"),
            RoutineState(resetHour: -1),
            RoutineState(resetHour: 24),
            RoutineState(resetMinute: -1),
            RoutineState(resetMinute: 60)
        ]
        for invalid in cases {
            XCTAssertThrowsError(try repository.save(invalid))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
