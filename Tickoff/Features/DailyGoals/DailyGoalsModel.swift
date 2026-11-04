import Foundation
import Observation

/// Loads today's goals and caches per-project rows and badges; the shell only routes its refreshes.
@MainActor @Observable
final class DailyGoalsModel {
    let store: DailyGoalStore
    private(set) var day = ""
    private(set) var rows: [Int64: [GoalDay]] = [:]
    private(set) var badges: [Int64: String] = [:]

    init(store: DailyGoalStore) {
        self.store = store
    }

    func reload(date: Date = .now, calendar: Calendar = .current) throws {
        let loaded = try store.loadToday(date: date, calendar: calendar)
        let grouped = Dictionary(grouping: loaded, by: { $0.goal.projectID })
        rows = grouped
        badges = grouped.mapValues { "\($0.filter(\.isComplete).count)/\($0.count)" }
        day = GoalDate.key(for: date, calendar: calendar)
    }

    func refreshIfNeeded(date: Date = .now, calendar: Calendar = .current) throws {
        if day != GoalDate.key(for: date, calendar: calendar) {
            try reload(date: date, calendar: calendar)
        }
    }

    /// Also checks after sleep resumes; scene activation requests an immediate check from the shell.
    func watchDayChanges(report: (Outcome) -> Void) async {
        while !_Concurrency.Task.isCancelled {
            do {
                try refreshIfNeeded()
            } catch {
                report(.failed(error.localizedDescription))
            }
            do {
                try await _Concurrency.Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                return
            } catch {
                report(.failed(error.localizedDescription))
                return
            }
        }
    }
}
