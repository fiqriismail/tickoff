//! Feature: the quick-add bar above the task list.

use eframe::egui::{self, Align, Key, Layout, Margin, TextEdit};
use rusqlite::Connection;

use crate::shared::outcome::Outcome;
use crate::shared::task::Priority;
use crate::shared::tasks;
use crate::shared::widgets::primary_button;

/// Matches the height of the title field so the picker and button line up with it.
const ROW_HEIGHT: f32 = 36.0;

pub struct AddTask {
    title: String,
    priority: Priority,
    focus_requested: bool,
}

impl AddTask {
    pub fn new() -> Self {
        Self {
            title: String::new(),
            priority: Priority::Medium,
            focus_requested: false,
        }
    }

    /// Puts the cursor in the title field on the next frame.
    pub fn focus(&mut self) {
        self.focus_requested = true;
    }

    pub fn show(&mut self, ui: &mut egui::Ui, conn: &Connection) -> Option<Outcome> {
        let mut outcome = None;

        ui.horizontal(|ui| {
            ui.spacing_mut().interact_size.y = ROW_HEIGHT;
            // Right-to-left so the button and picker sit on the right edge and
            // the title field takes whatever width is left.
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                let add_clicked = primary_button(ui, "+ Add").clicked();

                egui::ComboBox::from_id_salt("new_priority")
                    .selected_text(self.priority.label())
                    .width(90.0)
                    .show_ui(ui, |ui| {
                        for p in Priority::ALL {
                            ui.selectable_value(&mut self.priority, p, p.label());
                        }
                    });

                let response = ui.add(
                    TextEdit::singleline(&mut self.title)
                        .hint_text("Add a task and press Enter…")
                        .desired_width(ui.available_width())
                        .margin(Margin::symmetric(12, 9)),
                );
                if std::mem::take(&mut self.focus_requested) {
                    response.request_focus();
                }
                let submitted = response.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter));

                if add_clicked || submitted {
                    let title = self.title.trim();
                    if !title.is_empty() {
                        let result = tasks::insert(conn, title, self.priority);
                        if result.is_ok() {
                            self.title.clear();
                        }
                        outcome = Some(result.into());
                    }
                    response.request_focus();
                }
            });
        });

        outcome
    }
}
