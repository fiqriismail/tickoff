//! Feature: the "Edit task" dialog, including validation and the UPDATE.

use chrono::{Days, Local, NaiveDate};
use eframe::egui::{self, Align2, Key, Margin, TextEdit};
use rusqlite::{Connection, Result, params};

use crate::shared::outcome::Outcome;
use crate::shared::task::{DATE_FORMAT, Priority, Status, Task};
use crate::shared::theme;
use crate::shared::widgets::{caption, primary_button};

struct Draft {
    task: Task,
    error: Option<String>,
}

pub struct EditTask {
    draft: Option<Draft>,
}

impl EditTask {
    pub fn new() -> Self {
        Self { draft: None }
    }

    pub fn open(&mut self, task: Task) {
        self.draft = Some(Draft { task, error: None });
    }

    pub fn show(&mut self, ctx: &egui::Context, conn: &Connection) -> Option<Outcome> {
        let draft = self.draft.as_mut()?;

        let mut save = false;
        let mut cancel = false;

        egui::Window::new("Edit task")
            .collapsible(false)
            .resizable(false)
            .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
            .fixed_size([420.0, 0.0])
            .show(ctx, |ui| {
                let task = &mut draft.task;

                caption(ui, "Title");
                ui.add(
                    TextEdit::singleline(&mut task.title)
                        .desired_width(f32::INFINITY)
                        .margin(Margin::symmetric(10, 8)),
                );

                caption(ui, "Notes");
                ui.add(
                    TextEdit::multiline(&mut task.notes)
                        .desired_width(f32::INFINITY)
                        .desired_rows(4)
                        .margin(Margin::symmetric(10, 8)),
                );

                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        caption(ui, "Status");
                        egui::ComboBox::from_id_salt("edit_status")
                            .selected_text(task.status.label())
                            .show_ui(ui, |ui| {
                                for s in Status::ALL {
                                    ui.selectable_value(&mut task.status, s, s.label());
                                }
                            });
                    });
                    ui.vertical(|ui| {
                        caption(ui, "Priority");
                        egui::ComboBox::from_id_salt("edit_priority")
                            .selected_text(task.priority.label())
                            .show_ui(ui, |ui| {
                                for p in Priority::ALL {
                                    ui.selectable_value(&mut task.priority, p, p.label());
                                }
                            });
                    });
                });

                caption(ui, "Due date (YYYY-MM-DD)");
                ui.horizontal(|ui| {
                    ui.add(
                        TextEdit::singleline(&mut task.due)
                            .hint_text("none")
                            .desired_width(130.0)
                            .margin(Margin::symmetric(10, 8)),
                    );
                    let today = Local::now().date_naive();
                    if ui.button("Today").clicked() {
                        task.due = today.format(DATE_FORMAT).to_string();
                    }
                    if ui.button("Tomorrow").clicked() {
                        task.due = (today + Days::new(1)).format(DATE_FORMAT).to_string();
                    }
                    if ui.button("Clear").clicked() {
                        task.due.clear();
                    }
                });

                if let Some(error) = &draft.error {
                    ui.colored_label(theme::palette(ctx).red, error);
                }

                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    save = primary_button(ui, "Save").clicked();
                    cancel = ui.button("Cancel").clicked();
                });
            });

        ctx.input(|i| cancel |= i.key_pressed(Key::Escape));

        if save {
            match validate(draft.task.clone()) {
                Ok(task) => {
                    self.draft = None;
                    return Some(update(conn, &task).into());
                }
                Err(message) => draft.error = Some(message.to_owned()),
            }
        } else if cancel {
            self.draft = None;
        }
        None
    }
}

/// Trims the user's input and rejects tasks that cannot be saved.
fn validate(mut task: Task) -> std::result::Result<Task, &'static str> {
    task.title = task.title.trim().to_owned();
    task.due = task.due.trim().to_owned();

    if task.title.is_empty() {
        return Err("A task needs a title.");
    }
    if !task.due.is_empty() && NaiveDate::parse_from_str(&task.due, DATE_FORMAT).is_err() {
        return Err("Due date must look like 2026-12-31.");
    }
    Ok(task)
}

fn update(conn: &Connection, task: &Task) -> Result<usize> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shared::db;

    fn task(title: &str, due: &str) -> Task {
        Task {
            id: 1,
            title: title.into(),
            notes: String::new(),
            priority: Priority::Medium,
            status: Status::Todo,
            due: due.into(),
        }
    }

    #[test]
    fn validate_trims_and_accepts_good_input() {
        let ok = validate(task("  Ship it  ", " 2026-12-31 ")).unwrap();
        assert_eq!(ok.title, "Ship it");
        assert_eq!(ok.due, "2026-12-31");
        assert!(validate(task("No date", "")).is_ok());
    }

    #[test]
    fn validate_rejects_blank_titles_and_bad_dates() {
        assert!(validate(task("   ", "")).is_err());
        assert!(validate(task("Bad date", "31/12/2026")).is_err());
    }

    #[test]
    fn update_persists_every_field() {
        let conn = db::open_in_memory().unwrap();
        conn.execute("INSERT INTO tasks (title) VALUES ('old')", [])
            .unwrap();

        let edited = Task {
            id: conn.last_insert_rowid(),
            title: "new".into(),
            notes: "details".into(),
            priority: Priority::High,
            status: Status::InProgress,
            due: "2026-12-01".into(),
        };
        assert_eq!(update(&conn, &edited).unwrap(), 1);

        let (title, notes, priority, status, due): (String, String, i64, i64, String) = conn
            .query_row(
                "SELECT title, notes, priority, status, due FROM tasks WHERE id = ?1",
                [edited.id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
            )
            .unwrap();
        assert_eq!(
            (title.as_str(), notes.as_str(), priority, status, due.as_str()),
            ("new", "details", Priority::High.to_db(), Status::InProgress.to_db(), "2026-12-01")
        );
    }
}
