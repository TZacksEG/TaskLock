import Foundation
import XCTest
@testable import TaskLockCore

final class RoutineStateTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    func testEmptyStateIsDisabledAndDoesNotRequireCompletion() {
        let state = RoutineState()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertTrue(state.pendingTasks.isEmpty)
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.isEnabled)
    }

    func testPartialThenAllCompletionPreservesTaskOrder() {
        let first = DailyTask(title: "Walk")
        let second = DailyTask(title: "Breakfast")
        var state = RoutineState(tasks: [first, second])
        XCTAssertFalse(state.isComplete)
        state.completeTask(id: first.id)
        XCTAssertEqual(state.pendingTasks, [second])
        XCTAssertFalse(state.isComplete)
        state.completeTask(id: second.id)
        XCTAssertTrue(state.pendingTasks.isEmpty)
        XCTAssertTrue(state.isComplete)
    }

    func testUnknownAndDuplicateCompletionAreHarmless() {
        let task = DailyTask(title: "Walk")
        var state = RoutineState(tasks: [task])
        state.completeTask(id: UUID())
        XCTAssertTrue(state.completedIDs.isEmpty)
        state.completeTask(id: task.id)
        state.completeTask(id: task.id)
        XCTAssertEqual(state.completedIDs, [task.id])
    }

    func testMidnightResetsExactlyOnceAndSupportsSkippedDays() {
        let task = DailyTask(title: "Walk")
        var state = RoutineState(tasks: [task], completedIDs: [task.id], cycleKey: "2026-10-03")
        XCTAssertFalse(state.reconcile(at: date("2026-10-03T23:59:59Z"), calendar: calendar()))
        XCTAssertTrue(state.reconcile(at: date("2026-10-04T00:00:00Z"), calendar: calendar()))
        XCTAssertEqual(state.cycleKey, "2026-10-04")
        XCTAssertTrue(state.completedIDs.isEmpty)
        state.completeTask(id: task.id)
        XCTAssertFalse(state.reconcile(at: date("2026-10-04T06:00:00Z"), calendar: calendar()))
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.reconcile(at: date("2026-10-07T06:00:00Z"), calendar: calendar()))
        XCTAssertEqual(state.cycleKey, "2026-10-07")
        XCTAssertFalse(state.isComplete)
    }

    func testConfiguredBoundaryUsesPreviousDayBeforeReset() {
        XCTAssertEqual(RoutineState.cycleKey(at: date("2026-10-04T05:29:59Z"), resetHour: 5, resetMinute: 30, calendar: calendar()), "2026-10-03")
        XCTAssertEqual(RoutineState.cycleKey(at: date("2026-10-04T05:30:00Z"), resetHour: 5, resetMinute: 30, calendar: calendar()), "2026-10-04")
    }

    func testBoundaryUsesLocalTimezone() {
        let cairo = calendar("Africa/Cairo")
        XCTAssertEqual(RoutineState.cycleKey(at: date("2026-10-03T21:00:00Z"), resetHour: 0, resetMinute: 0, calendar: cairo), "2026-10-04")
    }

    func testSpringDSTNonexistentResetMovesToFirstValidTime() {
        let newYork = calendar("America/New_York")
        XCTAssertEqual(RoutineState.cycleKey(at: date("2026-03-08T06:59:59Z"), resetHour: 2, resetMinute: 30, calendar: newYork), "2026-03-07")
        XCTAssertEqual(RoutineState.cycleKey(at: date("2026-03-08T07:00:00Z"), resetHour: 2, resetMinute: 30, calendar: newYork), "2026-03-08")
    }

    func testAutumnDSTRepeatedResetOccursOnlyAtFirstOccurrence() {
        let newYork = calendar("America/New_York")
        let task = DailyTask(title: "Walk")
        var state = RoutineState(tasks: [task], completedIDs: [task.id], cycleKey: "2026-10-31", resetHour: 1, resetMinute: 30)
        XCTAssertFalse(state.reconcile(at: date("2026-11-01T05:29:59Z"), calendar: newYork))
        XCTAssertTrue(state.reconcile(at: date("2026-11-01T05:30:00Z"), calendar: newYork))
        state.completeTask(id: task.id)
        XCTAssertFalse(state.reconcile(at: date("2026-11-01T06:15:00Z"), calendar: newYork))
        XCTAssertFalse(state.reconcile(at: date("2026-11-01T06:30:00Z"), calendar: newYork))
        XCTAssertTrue(state.isComplete)
    }

    func testBackwardClockDoesNotEraseCompletionOrMoveCycleBackwards() {
        let task = DailyTask(title: "Walk")
        var state = RoutineState(tasks: [task], completedIDs: [task.id], cycleKey: "2026-10-04")
        XCTAssertFalse(state.reconcile(at: date("2026-10-02T08:00:00Z"), calendar: calendar()))
        XCTAssertEqual(state.cycleKey, "2026-10-04")
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.reconcile(at: date("2026-10-04T08:00:00Z"), calendar: calendar()))
        XCTAssertTrue(state.isComplete)
    }

    func testYearRolloverSortsCorrectly() {
        var state = RoutineState(cycleKey: "2026-12-31")
        XCTAssertTrue(state.reconcile(at: date("2027-01-01T00:00:00Z"), calendar: calendar()))
        XCTAssertEqual(state.cycleKey, "2027-01-01")
    }
}
