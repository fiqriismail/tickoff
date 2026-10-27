import Foundation
import Testing

@testable import Tickoff

struct DueLabelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24)) ?? .now }

    private func label(_ due: String, _ status: Status = .todo) -> DueLabel? {
        let task = Task(id: 1, title: "t", notes: "", priority: .medium, status: status, due: due)
        return DueLabel(for: task, today: today, calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    @Test func dueTodayAndTomorrowReadAsWords() {
        #expect(label("2026-10-24") == DueLabel(text: "Today", tone: .today))
        #expect(label("2026-10-25") == DueLabel(text: "Tomorrow", tone: .normal))
    }

    @Test func pastDatesAreOverdueAndFutureDatesShowTheDate() {
        #expect(label("2026-10-22") == DueLabel(text: "Overdue · Oct 22", tone: .overdue))
        #expect(label("2026-11-02") == DueLabel(text: "Nov 2", tone: .normal))
    }

    @Test func finishedTasksNeverShowAsOverdue() {
        #expect(label("2026-10-22", .done) == DueLabel(text: "Oct 22", tone: .normal))
    }

    @Test func missingOrInvalidDatesHaveNoLabel() {
        #expect(label("") == nil)
        #expect(label("soon") == nil)
        #expect(label("2026-02-31") == nil)
    }
}
