import Foundation
import Observation

/// The shell's state: the open database, the loaded tasks and the error banner message. It only
/// wires and routes; behaviour lives in the features, which report back with an `Outcome`.
@MainActor @Observable
final class AppModel {
    let database: AppDatabase
    let taskStore: TaskStore
    let settings: SettingsModel
    /// The single source of truth for tasks; features read it and never hold task data themselves.
    private(set) var tasks = TaskSet()
    /// Shown in the banner; set by a failed command or load, or at startup if the real database
    /// couldn't be opened and we fell back to a temporary one.
    private(set) var errorMessage: String?

    init(database: AppDatabase, startupError: String? = nil) {
        self.database = database
        taskStore = TaskStore(database: database)
        settings = SettingsModel(store: SettingsStore(database: database))
        errorMessage = startupError
        reload()
    }

    func reload() {
        do {
            tasks.replace(try taskStore.loadAll())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Records the outcome of a task change and reloads the tasks.
    func handle(_ outcome: Outcome) {
        report(outcome)
        reload()
    }

    /// Records an outcome that did not touch the tasks table, so no reload is needed.
    func report(_ outcome: Outcome) {
        switch outcome {
        case .changed: errorMessage = nil
        case .failed(let message): errorMessage = message
        }
    }

    func dismissError() {
        errorMessage = nil
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
