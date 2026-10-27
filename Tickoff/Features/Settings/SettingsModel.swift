import Observation

/// Holds the current appearance, applies edits immediately and saves each one.
@MainActor @Observable
final class SettingsModel {
    private(set) var appearance: Appearance
    /// Set when the last load or save failed; cleared by the next successful save.
    private(set) var errorMessage: String?

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        do {
            appearance = try store.load()
        } catch {
            appearance = .default
            errorMessage = "Couldn't load your settings: \(error.localizedDescription)"
        }
    }

    /// The change shows up at once; if saving fails it stays for this session and the error is set.
    func update(_ change: (inout Appearance) -> Void) {
        var edited = appearance
        change(&edited)
        guard edited != appearance else { return }
        appearance = edited
        save()
    }

    func resetToDefaults() {
        update { $0 = .default }
    }

    private func save() {
        do {
            try store.save(appearance)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save your settings: \(error.localizedDescription)"
        }
    }
}
