import Foundation
import Testing

@testable import Tickoff

struct TaskDraftTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func draft(_ title: String, due: String = "") -> TaskDraft {
        TaskDraft(
            task: Task(id: 1, title: title, notes: "", priority: .medium, status: .todo, due: due),
            calendar: calendar)
    }

    @Test func validationTrimsTheTitleAndKeepsTheDate() throws {
        let task = try draft("  Ship it  ", due: "2026-12-31").validated(calendar: calendar)
        #expect(task.title == "Ship it")
        #expect(task.due == "2026-12-31")
        #expect(try draft("No date").validated(calendar: calendar).due == "")
    }

    @Test func datesAreStoredZeroPadded() throws {
        #expect(try draft("Pad", due: "2026-1-5").validated(calendar: calendar).due == "2026-01-05")
    }

    @Test func blankTitlesAreRejectedWithAMessage() {
        #expect(throws: TaskDraft.ValidationError(message: "A task needs a title.")) {
            try draft("   ").validated(calendar: calendar)
        }
    }

    @Test func turningOffTheDueDateClearsIt() throws {
        var edited = draft("Task", due: "2026-12-31")
        edited.hasDue = false
        #expect(try edited.validated(calendar: calendar).due == "")
    }

    @Test func anUnreadableStoredDateStartsWithNoDueDate() {
        #expect(!draft("Task", due: "31/12/2026").hasDue)
    }

    @Test func editingKeepsTheOtherFields() throws {
        var edited = TaskDraft(
            task: Task(id: 9, title: "a", notes: "n", priority: .high, status: .inProgress, due: ""),
            calendar: calendar)
        edited.title = "b"
        let task = try edited.validated(calendar: calendar)
        #expect(task == Task(id: 9, title: "b", notes: "n", priority: .high, status: .inProgress, due: ""))
    }
}
