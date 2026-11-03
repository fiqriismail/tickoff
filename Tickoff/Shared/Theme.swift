/// The display options that live in the task list itself (Show Notes, Use Compact Rows). Theme,
/// accent and text size follow System Settings, so they are not app preferences. Features read
/// these through `Appearance`; `SettingsStore` persists them.
struct Appearance: Equatable, Sendable {
    var compactCards = false
    var showNotes = true

    static let `default` = Appearance()
}
