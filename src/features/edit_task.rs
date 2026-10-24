//! Feature: the "Edit task" dialog, including validation and the UPDATE.

use chrono::{Days, Local, NaiveDate};
use eframe::egui::{
    self, Align, CornerRadius, Frame, Id, Key, Layout, Margin, Modal, RichText, Stroke, TextEdit,
};
use rusqlite::Connection;

use crate::shared::outcome::Outcome;
use crate::shared::task::{DATE_FORMAT, Priority, Status, Task};
use crate::shared::tasks;
use crate::shared::theme;
use crate::shared::widgets::{caption, primary_button};

const DIALOG_WIDTH: f32 = 440.0;
const FIELD_MARGIN: Margin = Margin::symmetric(10, 8);

struct Draft {
    task: Task,
    error: Option<String>,
    focus_title: bool,
}

pub struct EditTask {
    draft: Option<Draft>,
}

impl EditTask {
    pub fn new() -> Self {
        Self { draft: None }
    }

    pub fn open(&mut self, task: Task) {
        self.draft = Some(Draft {
            task,
            error: None,
            focus_title: true,
        });
    }

    pub fn show(&mut self, ctx: &egui::Context, conn: &Connection) -> Option<Outcome> {
        let draft = self.draft.as_mut()?;
        let p = theme::palette(ctx);

        let mut save = false;
        let mut cancel = false;

        let frame = Frame::new()
            .fill(p.card)
            .stroke(Stroke::new(1.0, p.border))
            .corner_radius(CornerRadius::same(14))
            .inner_margin(Margin::same(24))
            .shadow(egui::Shadow {
                offset: [0, 8],
                blur: 28,
                spread: 0,
                color: egui::Color32::from_black_alpha(90),
            });

        let modal = Modal::new(Id::unique("tickoff::edit_task"))
            .frame(frame)
            .show(ctx, |ui| {
                ui.set_width(DIALOG_WIDTH);
                ui.spacing_mut().item_spacing.y = 6.0;
                let task = &mut draft.task;

                ui.label(RichText::new("Edit task").size(20.0).strong());
                ui.add_space(14.0);

                caption(ui, "Title");
                let title = ui.add(
                    TextEdit::singleline(&mut task.title)
                        .desired_width(f32::INFINITY)
                        .margin(FIELD_MARGIN),
                );
                if std::mem::take(&mut draft.focus_title) {
                    title.request_focus();
                }
                if title.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter)) {
                    save = true;
                }

                ui.add_space(10.0);
                caption(ui, "Notes");
                ui.add(
                    TextEdit::multiline(&mut task.notes)
                        .desired_width(f32::INFINITY)
                        .desired_rows(4)
                        .margin(FIELD_MARGIN),
                );

                ui.add_space(10.0);
                ui.columns(2, |columns| {
                    caption(&mut columns[0], "Status");
                    egui::ComboBox::from_id_salt("edit_status")
                        .selected_text(task.status.label())
                        .width(columns[0].available_width())
                        .show_ui(&mut columns[0], |ui| {
                            for s in Status::ALL {
                                ui.selectable_value(&mut task.status, s, s.label());
                            }
                        });

                    caption(&mut columns[1], "Priority");
                    egui::ComboBox::from_id_salt("edit_priority")
                        .selected_text(task.priority.label())
                        .width(columns[1].available_width())
                        .show_ui(&mut columns[1], |ui| {
                            for p in Priority::ALL {
                                ui.selectable_value(&mut task.priority, p, p.label());
                            }
                        });
                });

                ui.add_space(10.0);
                caption(ui, "Due date");
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 8.0;
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        // Right-to-left, so the buttons are added in reverse.
                        let today = Local::now().date_naive();
                        if ui.button("Clear").clicked() {
                            task.due.clear();
                        }
                        if ui.button("Tomorrow").clicked() {
                            task.due = (today + Days::new(1)).format(DATE_FORMAT).to_string();
                        }
                        if ui.button("Today").clicked() {
                            task.due = today.format(DATE_FORMAT).to_string();
                        }
                        ui.add(
                            TextEdit::singleline(&mut task.due)
                                .hint_text("YYYY-MM-DD")
                                .desired_width(ui.available_width())
                                .margin(FIELD_MARGIN),
                        );
                    });
                });

                if let Some(error) = &draft.error {
                    ui.add_space(4.0);
                    ui.colored_label(p.red, error);
                }

                ui.add_space(20.0);
                ui.horizontal(|ui| {
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        save |= primary_button(ui, "Save").clicked();
                        cancel |= ui.button("Cancel").clicked();
                    });
                });
            });

        // A stray click outside must not throw away edits, so only Escape closes it.
        if modal.is_top_modal && !modal.any_popup_open {
            cancel |= ctx.input_mut(|i| i.consume_key(egui::Modifiers::NONE, Key::Escape));
        }

        if save {
            match validate(draft.task.clone()) {
                Ok(task) => match tasks::update(conn, &task) {
                    Ok(_) => {
                        self.draft = None;
                        return Some(Outcome::Changed);
                    }
                    Err(e) => draft.error = Some(format!("Could not save: {e}")),
                },
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
    if !task.due.is_empty() {
        let date = NaiveDate::parse_from_str(&task.due, DATE_FORMAT)
            .map_err(|_| "Due date must look like 2026-12-31.")?;
        // The list sorts `due` as text, so only the zero-padded form may be stored.
        task.due = date.format(DATE_FORMAT).to_string();
    }
    Ok(task)
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn validate_stores_dates_in_canonical_form() {
        assert_eq!(validate(task("Pad", "2026-1-5")).unwrap().due, "2026-01-05");
    }

    #[test]
    fn validate_rejects_blank_titles_and_bad_dates() {
        assert!(validate(task("   ", "")).is_err());
        assert!(validate(task("Bad date", "31/12/2026")).is_err());
    }
}
