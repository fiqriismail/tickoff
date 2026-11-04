import SwiftUI

/// Selected-goal commands exposed to the shell's menu bar, never to another feature.
struct GoalActions {
    let edit: () -> Void
    let remove: () -> Void
    let increase: () -> Void
    let decrease: (() -> Void)?
    let increaseLabel: String
}

extension FocusedValues {
    @Entry var goalActions: GoalActions?
}
