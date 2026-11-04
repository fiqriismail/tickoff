import Foundation

/// The goal editor's draft validates text input before any persistence call.
struct GoalDraft {
    var id: Int64?
    var name = ""
    var tracking: GoalTracking = .checkOff
    var target = "1"

    init(goal: DailyGoal? = nil) {
        if let goal {
            id = goal.id
            name = goal.name
            tracking = goal.tracking
            target = String(goal.target)
        }
    }

    func validated(projectID: Int64) throws -> DailyGoal {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GoalError.blankName }
        let target = tracking == .checkOff ? 1 : Int(target)
        guard let target, target > 0 else { throw GoalError.invalidTarget }
        return DailyGoal(
            id: id ?? 0, projectID: projectID, name: name, tracking: tracking, target: target)
    }
}
