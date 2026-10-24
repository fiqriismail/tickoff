//! Feature: the task list — page header, search box and the task cards, plus
//! everything that happens *from* a card (toggle status, delete, request edit).

mod card;
mod store;

use chrono::Local;
use eframe::egui::{
    self, Align, CornerRadius, CursorIcon, Frame, Id, Key, Layout, Margin, RichText, Sense, Stroke,
    TextEdit, vec2,
};
use rusqlite::Connection;

use crate::shared::icons::{self, Icon};
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
        ui.vertical(|ui| {
            ui.spacing_mut().item_spacing.y = 4.0;
            ui.horizontal(|ui| {
                ui.heading(title);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    self.search_field(ui);
                });
            });
            ui.label(RichText::new(Local::now().format("%A, %-d %B").to_string()).color(p.muted));
        });
    }

    fn search_field(&mut self, ui: &mut egui::Ui) {
        let p = theme::palette(ui.ctx());
        let id = Id::unique("hello_gui::search");
        let focused = ui.memory(|m| m.has_focus(id));
        let stroke = if focused { p.accent } else { p.border };

        Frame::new()
            .fill(p.input)
            .stroke(Stroke::new(1.0, stroke))
            .corner_radius(CornerRadius::same(9))
            .inner_margin(Margin::symmetric(10, 4))
            .show(ui, |ui| {
                ui.spacing_mut().item_spacing.x = 6.0;
                ui.horizontal(|ui| {
                    // The header row lays out right-to-left, so children are added in reverse.
                    let (rect, clear) = ui.allocate_exact_size(vec2(icons::SIZE, icons::SIZE), Sense::click());
                    if !self.search.is_empty() {
                        let tint = if clear.hovered() { p.text } else { p.muted };
                        icons::paint(ui.painter(), rect.center(), Icon::Clear, tint);
                        if clear.on_hover_cursor(CursorIcon::PointingHand).clicked() {
                            self.search.clear();
                            ui.memory_mut(|m| m.request_focus(id));
                        }
                    }

                    let edit = ui.add(
                        TextEdit::singleline(&mut self.search)
                            .id(id)
                            .hint_text("Search")
                            .desired_width(170.0)
                            .frame(Frame::new()),
                    );
                    if std::mem::take(&mut self.focus_search) {
                        edit.request_focus();
                    }

                    let (rect, _) = ui.allocate_exact_size(vec2(icons::SIZE, icons::SIZE), Sense::hover());
                    icons::paint(ui.painter(), rect.center(), Icon::Search, p.muted);

                    if (edit.has_focus() || edit.lost_focus()) && ui.input(|i| i.key_pressed(Key::Escape)) {
                        if self.search.is_empty() {
                            edit.surrender_focus();
                        } else {
                            self.search.clear();
                        }
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
                let compact = theme::appearance(ui.ctx()).compact_cards;
                ui.spacing_mut().item_spacing.y = if compact { 8.0 } else { 14.0 };
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
                        let muted = theme::palette(ui.ctx()).muted;
                        if !query.is_empty() {
                            ui.label(RichText::new(format!("No results for “{}”", self.search.trim())).size(16.0).strong());
                            ui.label(RichText::new("Check the spelling or try a different search.").color(muted));
                        } else {
                            ui.label(RichText::new("🎉").size(40.0));
                            let message = if tasks.is_empty() {
                                "No tasks yet — add your first one above."
                            } else {
                                "Nothing here yet."
                            };
                            ui.label(RichText::new(message).color(muted));
                        }
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
