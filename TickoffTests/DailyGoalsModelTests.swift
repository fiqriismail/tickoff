import Foundation
import Testing

@testable import Tickoff

/// Today caches refresh on calendar changes without needing task-list work or real database files.
@MainActor
struct DailyGoalsModelTests {
    @Test func badgesAndRowsRefreshAfterProgressChangesAndDayRollover() throws {
        let database = try AppDatabase()
        let project = try ProjectStore(database: database).create(name: "Health", kind: .dailyGoals)
        let store = DailyGoalStore(database: database)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let id = try store.create(
            projectID: project, name: "Read", tracking: .checkOff, target: 1,
            date: today, calendar: calendar)
        let model = DailyGoalsModel(store: store)
        try model.reload(date: today, calendar: calendar)
        #expect(model.badges[project] == "0/1")
        try store.changeProgress(id: id, increment: true, date: today, calendar: calendar)
        try model.reload(date: today, calendar: calendar)
        #expect(model.badges[project] == "1/1")
        try model.refreshIfNeeded(date: tomorrow, calendar: calendar)
        #expect(model.day == "2026-11-05")
        #expect(model.badges[project] == "0/1")
        #expect(model.rows[project]?.first?.value == 0)
    }

    @Test func dayKeysFollowLocalDatesAcrossDaylightSavingAndTimeZoneChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let next = calendar.date(byAdding: .day, value: 1, to: first)!
        #expect(next.timeIntervalSince(first) == 25 * 60 * 60)
        #expect(GoalDate.key(for: first, calendar: calendar) == "2026-11-01")
        #expect(GoalDate.key(for: next, calendar: calendar) == "2026-11-02")
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(GoalDate.key(for: next, calendar: calendar) == "2026-11-01")
    }
}
