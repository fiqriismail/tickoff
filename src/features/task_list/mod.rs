//! Feature: the task list — page header, search box and the task cards, plus
//! everything that happens *from* a card (toggle status, delete, request edit).

mod card;
mod store;

use chrono::Local;
use eframe::egui::{self, Align, Layout, Margin, RichText, TextEdit};
use rusqlite::Connection;

use crate::shared::outcome::Outcome;
use crate::shared::task::Task;
use crate::shared::theme;

use card::Action;

pub use store::load_all;

/// What the list asks the shell to do.
pub enum Event {
    /// A card's edit button was pressed; the shell routes this to the edit dialog.
    Edit(Task),
    Outcome(Outcome),
}

pub struct TaskList {
    search: String,
    focus_search: bool,
}

impl TaskList {
    pub fn new() -> Self {
        Self {
            search: String::new(),
            focus_search: false,
        }
    }

    /// Puts the cursor in the search box on the next frame.
    pub fn focus_search(&mut self) {
        self.focus_search = true;
    }

    pub fn header(&mut self, ui: &mut egui::Ui, title: &str) {
        let p = theme::palette(ui.ctx());
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.heading(title);
                ui.label(
                    RichText::new(Local::now().format("%A, %-d %B").to_string()).color(p.muted),
                );
            });
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                let search = ui.add(
                    TextEdit::singleline(&mut self.search)
                        .hint_text("Search tasks…")
                        .desired_width(220.0)
                        .margin(Margin::symmetric(10, 8)),
                );
                if std::mem::take(&mut self.focus_search) {
                    search.request_focus();
                }
            });
        });
    }

    /// Shows the cards for every task in `tasks` that passes `visible` and the search box.
    pub fn show(
        &mut self,
        ui: &mut egui::Ui,
        conn: &Connection,
        tasks: &[Task],
        visible: impl Fn(&Task) -> bool,
    ) -> Option<Event> {
        let query = self.search.trim().to_lowercase();
        let today = Local::now().date_naive();
        let mut action = None;
        let mut shown = 0;

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                for task in tasks
                    .iter()
                    .filter(|t| visible(t) && matches_query(t, &query))
                {
                    shown += 1;
                    if let Some(a) = card::show(ui, task, today) {
                        action = Some(a);
                    }
                }

                if shown == 0 {
                    ui.add_space(60.0);
                    ui.vertical_centered(|ui| {
                        ui.label(RichText::new("🎉").size(40.0));
                        let message = if tasks.is_empty() {
                            "No tasks yet — add your first one above."
                        } else {
                            "Nothing matches here."
                        };
                        ui.label(RichText::new(message).color(theme::palette(ui.ctx()).muted));
                    });
                }
            });

        match action? {
            Action::Edit(task) => Some(Event::Edit(task)),
            Action::SetStatus(id, status) => {
                Some(Event::Outcome(store::set_status(conn, id, status).into()))
            }
            Action::Delete(id) => Some(Event::Outcome(store::delete(conn, id).into())),
        }
    }
}

fn matches_query(task: &Task, query: &str) -> bool {
    query.is_empty()
        || task.title.to_lowercase().contains(query)
        || task.notes.to_lowercase().contains(query)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shared::task::{Priority, Status};

    fn task(title: &str, notes: &str) -> Task {
        Task {
            id: 1,
            title: title.into(),
            notes: notes.into(),
            priority: Priority::Medium,
            status: Status::Todo,
            due: String::new(),
        }
    }

    #[test]
    fn search_matches_title_or_notes_case_insensitively() {
        let t = task("Buy Groceries", "milk and eggs");
        assert!(matches_query(&t, ""));
        assert!(matches_query(&t, "grocer"));
        assert!(matches_query(&t, "eggs"));
        assert!(!matches_query(&t, "invoice"));
    }
}
