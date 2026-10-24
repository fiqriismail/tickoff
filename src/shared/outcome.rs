use rusqlite::Result;

/// What a feature reports back to the shell after it ran a database command.
pub enum Outcome {
    /// The data changed; the shell should reload and clear any error banner.
    Changed,
    /// The command failed; the shell should show the message and reload.
    Failed(String),
}

impl<T> From<Result<T>> for Outcome {
    fn from(result: Result<T>) -> Self {
        match result {
            Ok(_) => Outcome::Changed,
            Err(e) => Outcome::Failed(e.to_string()),
        }
    }
}
