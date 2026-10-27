import Foundation
import Observation

/// The shell's state: the open database and the features' models. It only wires and routes;
/// behaviour lives in the features. #15 grows this with the task list and error banner.
@MainActor @Observable
final class AppModel {
    let database: AppDatabase
    let settings: SettingsModel
    /// Set when the real database couldn't be opened and we fell back to a temporary one.
    let startupError: String?

    init(database: AppDatabase, startupError: String? = nil) {
        self.database = database
        self.startupError = startupError
        settings = SettingsModel(store: SettingsStore(database: database))
    }

    /// Opens `~/.hello_gui/tasks.db`; on failure runs on an in-memory database and records why.
    static func launch() -> AppModel {
        // Hosted unit tests start the app too, and must never open the real database.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return temporary(startupError: nil)
        }
        do {
            return AppModel(database: try AppDatabase.openDefault())
        } catch {
            return temporary(
                startupError: "Couldn't open your tasks database: \(error.localizedDescription)")
        }
    }

    private static func temporary(startupError: String?) -> AppModel {
        // An in-memory SQLite database only fails if SQLite itself is unusable.
        guard let database = try? AppDatabase() else { fatalError("SQLite is unavailable") }
        return AppModel(database: database, startupError: startupError)
    }
}
