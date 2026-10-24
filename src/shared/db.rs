use std::error::Error;
use std::path::PathBuf;

use rusqlite::{Connection, Result};

pub fn open() -> Result<Connection, Box<dyn Error + Send + Sync>> {
    let conn = Connection::open(db_path()?)?;
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

/// `<home>/.hello_gui/tasks.db`, created on first run.
fn db_path() -> Result<PathBuf, Box<dyn Error + Send + Sync>> {
    let home = dirs::home_dir().ok_or("could not find your home directory")?;
    let dir = home.join(".hello_gui");
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("could not create {}: {e}", dir.display()))?;
    Ok(dir.join("tasks.db"))
}
