use chrono::NaiveDate;
use eframe::egui::{
    self, Align, Button, Color32, CornerRadius, Frame, Layout, Margin, RichText, Sense, Stroke,
    UiBuilder, vec2,
};

use crate::shared::task::{Priority, Status, Task};
use crate::shared::theme::{self, Palette};

pub enum Action {
    SetStatus(i64, Status),
    Edit(Task),
    Delete(i64),
}

/// Width kept free on the right of a card for the Edit and Delete buttons.
const BUTTONS_WIDTH: f32 = 130.0;

pub fn show(ui: &mut egui::Ui, task: &Task, today: NaiveDate) -> Option<Action> {
    let p = theme::palette(ui.ctx());
    let look = theme::appearance(ui.ctx());
    let compact = look.compact_cards;
    let mut action = None;
    let done = task.is_done();
    let margin = if compact { Margin::symmetric(16, 9) } else { Margin::symmetric(22, 20) };

    let card = ui.scope_builder(UiBuilder::new().sense(Sense::click()), |ui| {
        Frame::new()
            .fill(p.card)
            .stroke(Stroke::new(1.0, p.border))
            .corner_radius(CornerRadius::same(12))
            .inner_margin(margin)
            .show(ui, |ui| {
                ui.set_width(ui.available_width());
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = if compact { 12.0 } else { 16.0 };
                    if status_circle(ui, &p, task.status).clicked() {
                        let next = if done { Status::Todo } else { Status::Done };
                        action = Some(Action::SetStatus(task.id, next));
                    }

                    ui.vertical(|ui| {
                        ui.set_max_width((ui.available_width() - BUTTONS_WIDTH).max(160.0));
                        ui.spacing_mut().item_spacing.y = if compact { 3.0 } else { 10.0 };

                        let mut title = RichText::new(&task.title).size(16.0).strong();
                        if done {
                            title = title.strikethrough().color(p.muted);
                        }

                        if compact {
                            ui.horizontal_wrapped(|ui| {
                                ui.spacing_mut().item_spacing = vec2(8.0, 3.0);
                                ui.label(title);
                                meta(ui, &p, task, today, &mut action);
                            });
                        } else {
                            ui.label(title);
                        }

                        if look.show_notes && !task.notes.is_empty() {
                            let first_line = task.notes.lines().next().unwrap_or_default();
                            ui.label(RichText::new(first_line).small().color(p.muted));
                        }

                        if !compact {
                            ui.add_space(2.0);
                            ui.horizontal_wrapped(|ui| {
                                ui.spacing_mut().item_spacing = vec2(8.0, 6.0);
                                meta(ui, &p, task, today, &mut action);
                            });
                        }
                    });

                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if text_button(ui, &p, "Delete", "Delete this task").clicked() {
                            action = Some(Action::Delete(task.id));
                        }
                        if text_button(ui, &p, "Edit", "Edit this task").clicked() {
                            action = Some(Action::Edit(task.clone()));
                        }
                    });
                });
            });
    });

    card.response.context_menu(|ui| {
        if ui.button("Edit…").clicked() {
            action = Some(Action::Edit(task.clone()));
        }
        let toggle = if done {
            "Mark as To do"
        } else {
            "Mark as Done"
        };
        if ui.button(toggle).clicked() {
            let next = if done { Status::Todo } else { Status::Done };
            action = Some(Action::SetStatus(task.id, next));
        }
        ui.separator();
        if ui.button("Delete").clicked() {
            action = Some(Action::Delete(task.id));
        }
        if action.is_some() {
            ui.close();
        }
    });

    action
}

fn meta(ui: &mut egui::Ui, p: &Palette, task: &Task, today: NaiveDate, action: &mut Option<Action>) {
    let status = pill(ui, task.status.label(), status_color(p, task.status))
        .interact(Sense::click())
        .on_hover_text("Click to move to the next status")
        .on_hover_cursor(egui::CursorIcon::PointingHand);
    if status.clicked() {
        *action = Some(Action::SetStatus(task.id, task.status.next()));
    }
    pill(ui, task.priority.label(), priority_color(p, task.priority));
    if let Some((text, color)) = due_label(p, task, today) {
        ui.label(RichText::new(text).small().color(color));
    }
}

fn priority_color(p: &Palette, priority: Priority) -> Color32 {
    match priority {
        Priority::Low => p.blue,
        Priority::Medium => p.amber,
        Priority::High => p.red,
    }
}

fn status_color(p: &Palette, status: Status) -> Color32 {
    match status {
        Status::Todo => p.muted,
        Status::InProgress => p.accent,
        Status::Done => p.green,
    }
}

fn due_label(p: &Palette, task: &Task, today: NaiveDate) -> Option<(String, Color32)> {
    let date = task.due_date()?;
    let short = date.format("%b %-d").to_string();
    let (text, color) = if task.is_done() {
        (short, p.muted)
    } else {
        match (date - today).num_days() {
            i64::MIN..=-1 => (format!("Overdue · {short}"), p.red),
            0 => ("Today".to_owned(), p.amber),
            1 => ("Tomorrow".to_owned(), p.muted),
            _ => (short, p.muted),
        }
    };
    Some((format!("📅 {text}"), color))
}

fn pill(ui: &mut egui::Ui, text: &str, color: Color32) -> egui::Response {
    Frame::new()
        .fill(color.gamma_multiply(0.16))
        .corner_radius(CornerRadius::same(10))
        .inner_margin(Margin::symmetric(9, 2))
        .show(ui, |ui| {
            ui.label(RichText::new(text).small().strong().color(color));
        })
        .response
}

fn text_button(ui: &mut egui::Ui, p: &Palette, text: &str, tooltip: &str) -> egui::Response {
    ui.add(
        Button::new(RichText::new(text).small().color(p.muted))
            .fill(Color32::TRANSPARENT)
            .stroke(Stroke::NONE),
    )
    .on_hover_text(tooltip)
    .on_hover_cursor(egui::CursorIcon::PointingHand)
}

fn status_circle(ui: &mut egui::Ui, p: &Palette, status: Status) -> egui::Response {
    let (rect, response) = ui.allocate_exact_size(vec2(24.0, 24.0), Sense::click());
    let center = rect.center();
    let painter = ui.painter();
    let ring = if response.hovered() {
        p.accent
    } else {
        status_color(p, status)
    };

    match status {
        Status::Done => {
            painter.circle_filled(center, 10.0, p.green);
            let check = [
                center + vec2(-4.5, 0.5),
                center + vec2(-1.5, 3.5),
                center + vec2(4.5, -3.0),
            ];
            painter.line(check.to_vec(), Stroke::new(2.0, p.card));
        }
        Status::InProgress => {
            painter.circle_stroke(center, 10.0, Stroke::new(2.0, ring));
            painter.circle_filled(center, 4.5, p.accent);
        }
        Status::Todo => {
            painter.circle_stroke(center, 10.0, Stroke::new(2.0, ring));
        }
    }
    response.on_hover_cursor(egui::CursorIcon::PointingHand)
}

#[cfg(test)]
mod tests {
    use super::*;
    use eframe::egui::Theme;

    use crate::shared::theme::Accent;

    fn task(status: Status, due: &str) -> Task {
        Task {
            id: 1,
            title: "t".into(),
            notes: String::new(),
            priority: Priority::Medium,
            status,
            due: due.into(),
        }
    }

    fn label(task: &Task) -> Option<String> {
        let today = NaiveDate::from_ymd_opt(2026, 10, 24).unwrap();
        let palette = Palette::new(Theme::Dark, Accent::Indigo);
        due_label(&palette, task, today).map(|(text, _)| text)
    }

    #[test]
    fn due_labels_are_relative_to_today() {
        assert_eq!(
            label(&task(Status::Todo, "2026-10-24")).unwrap(),
            "📅 Today"
        );
        assert_eq!(
            label(&task(Status::Todo, "2026-10-25")).unwrap(),
            "📅 Tomorrow"
        );
        assert_eq!(
            label(&task(Status::Todo, "2026-10-22")).unwrap(),
            "📅 Overdue · Oct 22"
        );
        assert_eq!(
            label(&task(Status::Todo, "2026-11-02")).unwrap(),
            "📅 Nov 2"
        );
    }

    #[test]
    fn finished_tasks_are_never_overdue_and_undated_tasks_have_no_label() {
        assert_eq!(
            label(&task(Status::Done, "2026-10-22")).unwrap(),
            "📅 Oct 22"
        );
        assert!(label(&task(Status::Todo, "")).is_none());
    }
}
