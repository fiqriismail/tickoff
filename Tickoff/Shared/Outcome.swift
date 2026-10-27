/// What a feature reports back to the shell after it ran a database command.
enum Outcome: Equatable, Sendable {
    /// The data changed: the shell reloads and clears the error banner.
    case changed
    /// The command failed: the shell shows the message and reloads.
    case failed(String)

    /// Runs `work`, turning a thrown error into `.failed` so it can never crash the app.
    static func run(_ work: () throws -> Void) -> Outcome {
        do {
            try work()
            return .changed
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
