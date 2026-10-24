use std::path::PathBuf;

use rusqlite::{Connection, Result};

pub fn open() -> Result<Connection> {
    let conn = Connection::open(db_path())?;
    migrate(&conn)?;
    Ok(conn)
}

#[cfg(test)]
pub fn open_in_memory() -> Result<Connection> {
    let conn = Connection::open_in_memory()?;
    migrate(&conn)?;
    Ok(conn)
}

fn migrate(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tasks (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            title      TEXT    NOT NULL,
            notes      TEXT    NOT NULL DEFAULT '',
            priority   INTEGER NOT NULL DEFAULT 1,
            status     INTEGER NOT NULL DEFAULT 0,
            due        TEXT    NOT NULL DEFAULT '',
            created_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );",
    )
}

/// `~/.hello_gui/tasks.db`, falling back to the working directory.
fn db_path() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        let dir = PathBuf::from(home).join(".hello_gui");
        if std::fs::create_dir_all(&dir).is_ok() {
            return dir.join("tasks.db");
        }
    }
    PathBuf::from("tasks.db")
}
