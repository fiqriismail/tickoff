//! The one place that talks SQL about the `tasks` table.

use rusqlite::{Connection, Result, Row, params};

use super::task::{Priority, Status, Task};

/// The loaded tasks plus everything derived from them, computed once per load
/// instead of once per frame.
pub struct TaskSet {
    items: Vec<Task>,
    /// Lower-cased title and notes of each task, for case-insensitive search.
    search_keys: Vec<String>,
    counts: [usize; 3],
    revision: u64,
}

impl TaskSet {
    pub fn new() -> Self {
        Self {
            items: Vec::new(),
            search_keys: Vec::new(),
            counts: [0; 3],
            revision: 0,
        }
    }

    /// Swaps in freshly loaded tasks and bumps [`TaskSet::revision`].
    pub fn replace(&mut self, items: Vec<Task>) {
        self.search_keys = items
            .iter()
            .map(|t| format!("{}\n{}", t.title, t.notes).to_lowercase())
            .collect();
        self.counts = [0; 3];
        for task in &items {
            self.counts[task.status.to_db() as usize] += 1;
        }
        self.items = items;
        self.revision += 1;
    }

    pub fn items(&self) -> &[Task] {
        &self.items
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// Changes every time the contents are replaced; caches key on it.
    pub fn revision(&self) -> u64 {
        self.revision
    }

    /// Number of tasks with `status`, or of all tasks when it is `None`.
    pub fn count(&self, status: Option<Status>) -> usize {
        match status {
            Some(s) => self.counts[s.to_db() as usize],
            None => self.items.len(),
        }
    }

    /// Whether task `index` contains `query`, which must already be lower-case.
    pub fn matches(&self, index: usize, query: &str) -> bool {
        query.is_empty() || self.search_keys[index].contains(query)
    }
}

/// Open tasks first, then by priority, then by due date (undated last), newest first.
pub fn load_all(conn: &Connection) -> Result<Vec<Task>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, notes, priority, status, due FROM tasks
         ORDER BY (status = 2), priority DESC, (due = ''), due, id DESC",
    )?;
    stmt.query_map([], row_to_task)?.collect()
}

pub fn insert(conn: &Connection, title: &str, priority: Priority) -> Result<i64> {
    conn.execute(
        "INSERT INTO tasks (title, priority) VALUES (?1, ?2)",
        params![title, priority.to_db()],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn update(conn: &Connection, task: &Task) -> Result<usize> {
    conn.execute(
        "UPDATE tasks SET title = ?1, notes = ?2, priority = ?3, status = ?4, due = ?5
         WHERE id = ?6",
        params![
            task.title,
            task.notes,
            task.priority.to_db(),
            task.status.to_db(),
            task.due,
            task.id
        ],
    )
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

pub fn clear_completed(conn: &Connection) -> Result<usize> {
    conn.execute(
        "DELETE FROM tasks WHERE status = ?1",
        [Status::Done.to_db()],
    )
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
    fn task_set_counts_and_searches_without_rescanning() {
        let mut set = TaskSet::new();
        let make = |title: &str, status| Task {
            id: 1,
            title: title.into(),
            notes: "Milk".into(),
            priority: Priority::Medium,
            status,
            due: String::new(),
        };
        set.replace(vec![make("Buy Eggs", Status::Todo), make("Call", Status::Done)]);

        assert_eq!(set.count(None), 2);
        assert_eq!(set.count(Some(Status::Done)), 1);
        assert_eq!(set.count(Some(Status::InProgress)), 0);
        assert!(set.matches(0, "eggs") && set.matches(0, "milk") && set.matches(0, ""));
        assert!(!set.matches(1, "eggs"));

        let before = set.revision();
        set.replace(Vec::new());
        assert!(set.revision() > before);
    }

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

        let titles: Vec<String> = load_all(&conn)
            .unwrap()
            .into_iter()
            .map(|t| t.title)
            .collect();
        assert_eq!(titles, ["high dated", "high undated", "low", "done high"]);
    }

    #[test]
    fn insert_creates_a_todo_task_with_the_given_priority() {
        let conn = db::open_in_memory().unwrap();
        let id = insert(&conn, "Write tests", Priority::High).unwrap();

        let task = load_all(&conn).unwrap().remove(0);
        assert_eq!(task.id, id);
        assert_eq!(task.title, "Write tests");
        assert_eq!(task.priority, Priority::High);
        assert_eq!(task.status, Status::Todo);
    }

    #[test]
    fn update_persists_every_field() {
        let conn = db::open_in_memory().unwrap();
        let id = insert(&conn, "old", Priority::Low).unwrap();

        let edited = Task {
            id,
            title: "new".into(),
            notes: "details".into(),
            priority: Priority::High,
            status: Status::InProgress,
            due: "2026-12-01".into(),
        };
        assert_eq!(update(&conn, &edited).unwrap(), 1);

        let saved = load_all(&conn).unwrap().remove(0);
        assert_eq!(
            (saved.title.as_str(), saved.notes.as_str(), saved.priority, saved.status, saved.due.as_str()),
            ("new", "details", Priority::High, Status::InProgress, "2026-12-01")
        );
    }

    #[test]
    fn set_status_and_delete_affect_only_the_given_task() {
        let conn = db::open_in_memory().unwrap();
        let a = insert(&conn, "a", Priority::Medium).unwrap();
        let b = insert(&conn, "b", Priority::Medium).unwrap();

        set_status(&conn, a, Status::Done).unwrap();
        delete(&conn, b).unwrap();

        let tasks = load_all(&conn).unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].id, a);
        assert_eq!(tasks[0].status, Status::Done);
    }

    #[test]
    fn clear_completed_only_removes_done_tasks() {
        let conn = db::open_in_memory().unwrap();
        conn.execute_batch(
            "INSERT INTO tasks (title, status) VALUES ('a', 0), ('b', 1), ('c', 2), ('d', 2);",
        )
        .unwrap();

        assert_eq!(clear_completed(&conn).unwrap(), 2);
        assert_eq!(load_all(&conn).unwrap().len(), 2);
    }
}
