/// The toolbar subtitle that reports how much of the chosen project is done. A pure function so
/// the wording is tested without a view.
enum ProgressSummary {
    static func text(done: Int, total: Int) -> String {
        total == 0 ? "No tasks" : "\(done) of \(total) completed"
    }
}
