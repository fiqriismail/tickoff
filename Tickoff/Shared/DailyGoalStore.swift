import Foundation
import GRDB

/// Owns SQL for goal definitions and their per-day snapshots. History is never deleted by goal removal.
struct DailyGoalStore: Sendable {
    let database: AppDatabase

    /// Materializes zero-progress snapshots once per active day, never resetting existing rows.
    func loadToday(date: Date, calendar: Calendar = .current) throws -> [GoalDay] {
        let day = GoalDate.key(for: date, calendar: calendar)
        return try database.queue.write { db in
            let projects = try ProjectStore.dailyGoalProjectIDs(activeOnly: true, in: db)
            var result: [GoalDay] = []
            for projectID in projects {
                try db.execute(
                    sql: """
                        INSERT INTO daily_goal_progress (goal_id, day, name, tracking, target)
                        SELECT id, ?, name, tracking, target FROM daily_goals
                        WHERE project_id = ? AND removed = 0
                        ON CONFLICT (goal_id, day) DO NOTHING
                        """, arguments: [day, projectID])
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT g.id, g.project_id, g.name, g.tracking, g.target,
                               p.name AS daily_name, p.tracking AS daily_tracking,
                               p.target AS daily_target, p.value
                        FROM daily_goals g
                        JOIN daily_goal_progress p ON p.goal_id = g.id AND p.day = ?
                        WHERE g.project_id = ? AND g.removed = 0 ORDER BY g.id
                        """, arguments: [day, projectID])
                for row in rows {
                    guard let tracking = GoalTracking(rawValue: row["daily_tracking"]) else {
                        throw GoalError.unavailable
                    }
                    result.append(GoalDay(
                        goal: try Self.goal(from: row), day: day, name: row["daily_name"],
                        tracking: tracking, target: row["daily_target"], value: row["value"]))
                }
            }
            return result
        }
    }

    @discardableResult
    func create(
        projectID: Int64, name: String, tracking: GoalTracking, target: Int,
        date: Date = .now, calendar: Calendar = .current
    ) throws -> Int64 {
        let name = try Self.validate(name: name, tracking: tracking, target: target)
        return try database.queue.write { db in
            try ProjectStore.requireKind(.dailyGoals, id: projectID, activeOnly: true, in: db)
            let target = tracking == .checkOff ? 1 : target
            try db.execute(
                sql: "INSERT INTO daily_goals (project_id, name, tracking, target) VALUES (?, ?, ?, ?)",
                arguments: [projectID, name, tracking.rawValue, target])
            let id = db.lastInsertedRowID
            try Self.snapshot(
                DailyGoal(id: id, projectID: projectID, name: name, tracking: tracking, target: target),
                day: GoalDate.key(for: date, calendar: calendar), in: db)
            return id
        }
    }

    /// Freeze today's definition before changing the template that tomorrow will use.
    func update(_ goal: DailyGoal, date: Date = .now, calendar: Calendar = .current) throws {
        let name = try Self.validate(name: goal.name, tracking: goal.tracking, target: goal.target)
        try database.queue.write { db in
            let existing = try Self.requireGoal(goal.id, in: db)
            guard existing.projectID == goal.projectID else { throw GoalError.unavailable }
            try Self.snapshot(existing, day: GoalDate.key(for: date, calendar: calendar), in: db)
            try db.execute(
                sql: "UPDATE daily_goals SET name = ?, tracking = ?, target = ? WHERE id = ?",
                arguments: [
                    name, goal.tracking.rawValue, goal.tracking == .checkOff ? 1 : goal.target, goal.id,
                ])
        }
    }

    func remove(id: Int64) throws {
        try database.queue.write { db in
            _ = try Self.requireGoal(id, in: db)
            try db.execute(sql: "UPDATE daily_goals SET removed = 1 WHERE id = ?", arguments: [id])
        }
    }

    /// Resolve the day at the moment of the action, not from a possibly stale row displayed before midnight.
    func changeProgress(
        id: Int64, increment: Bool, date: Date = .now, calendar: Calendar = .current
    ) throws {
        try database.queue.write { db in
            let goal = try Self.requireGoal(id, in: db)
            let day = GoalDate.key(for: date, calendar: calendar)
            try Self.snapshot(goal, day: day, in: db)
            guard let row = try Row.fetchOne(
                db, sql: "SELECT tracking, value FROM daily_goal_progress WHERE goal_id = ? AND day = ?",
                arguments: [id, day])
            else { throw GoalError.unavailable }
            let value: Int = row["value"]
            let tracking: String = row["tracking"]
            let next: Int
            if tracking == GoalTracking.checkOff.rawValue {
                next = value == 0 ? 1 : 0
            } else {
                if increment && value == Int.max { throw GoalError.progressLimit }
                next = increment ? value + 1 : max(0, value - 1)
            }
            try db.execute(
                sql: "UPDATE daily_goal_progress SET value = ? WHERE goal_id = ? AND day = ?",
                arguments: [next, id, day])
        }
    }

    /// Project deletion hides definitions too, but historical snapshots stay intact.
    static func removeGoals(inProject projectID: Int64, in db: Database) throws {
        try db.execute(
            sql: "UPDATE daily_goals SET removed = 1 WHERE project_id = ?", arguments: [projectID])
    }

    private static func requireGoal(_ id: Int64, in db: Database) throws -> DailyGoal {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT id, project_id, name, tracking, target FROM daily_goals WHERE id = ? AND removed = 0",
            arguments: [id])
        else { throw GoalError.unavailable }
        let goal = try goal(from: row)
        try ProjectStore.requireKind(.dailyGoals, id: goal.projectID, activeOnly: true, in: db)
        return goal
    }

    private static func goal(from row: Row) throws -> DailyGoal {
        guard let tracking = GoalTracking(rawValue: row["tracking"]) else { throw GoalError.unavailable }
        return DailyGoal(
            id: row["id"], projectID: row["project_id"], name: row["name"],
            tracking: tracking, target: row["target"])
    }

    private static func snapshot(_ goal: DailyGoal, day: String, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO daily_goal_progress (goal_id, day, name, tracking, target)
                VALUES (?, ?, ?, ?, ?) ON CONFLICT (goal_id, day) DO NOTHING
                """, arguments: [goal.id, day, goal.name, goal.tracking.rawValue, goal.target])
    }

    private static func validate(name: String, tracking: GoalTracking, target: Int) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GoalError.blankName }
        guard tracking == .checkOff || target > 0 else { throw GoalError.invalidTarget }
        return trimmed
    }
}
