use rusqlite::{Connection, Result, Row};

use crate::shared::task::{Priority, Status, Task};

/// Open tasks first, then by priority, then by due date (undated last), newest first.
pub fn load_all(conn: &Connection) -> Result<Vec<Task>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, notes, priority, status, due FROM tasks
         ORDER BY (status = 2), priority DESC, (due = ''), due, id DESC",
    )?;
    stmt.query_map([], row_to_task)?.collect()
}

pub fn set_status(conn: &Connection, id: i64, status: Status) -> Result<usize> {
    conn.execute(
        "UPDATE tasks SET status = ?1 WHERE id = ?2",
        (status.to_db(), id),
    )
}

pub fn delete(conn: &Connection, id: i64) -> Result<usize> {
    conn.execute("DELETE FROM tasks WHERE id = ?1", [id])
}

fn row_to_task(row: &Row) -> Result<Task> {
    Ok(Task {
        id: row.get(0)?,
        title: row.get(1)?,
        notes: row.get(2)?,
        priority: Priority::from_db(row.get(3)?),
        status: Status::from_db(row.get(4)?),
        due: row.get(5)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shared::db;

    #[test]
    fn load_all_orders_open_high_priority_dated_tasks_first() {
        let conn = db::open_in_memory().unwrap();
        conn.execute_batch(
            "INSERT INTO tasks (title, priority, status, due) VALUES
                ('done high',   2, 2, ''),
                ('low',         0, 0, ''),
                ('high undated',2, 0, ''),
                ('high dated',  2, 0, '2026-12-01');",
        )
        .unwrap();

        let titles: Vec<String> = load_all(&conn).unwrap().into_iter().map(|t| t.title).collect();
        assert_eq!(titles, ["high dated", "high undated", "low", "done high"]);
    }

    #[test]
    fn set_status_and_delete_affect_only_the_given_task() {
        let conn = db::open_in_memory().unwrap();
        conn.execute_batch("INSERT INTO tasks (title) VALUES ('a'), ('b');")
            .unwrap();
        let ids: Vec<i64> = load_all(&conn).unwrap().iter().map(|t| t.id).collect();

        set_status(&conn, ids[0], Status::Done).unwrap();
        delete(&conn, ids[1]).unwrap();

        let tasks = load_all(&conn).unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].id, ids[0]);
        assert_eq!(tasks[0].status, Status::Done);
    }
}
