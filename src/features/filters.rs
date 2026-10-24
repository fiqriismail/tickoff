//! Feature: the sidebar — status filters, progress summary and "Clear completed".

use eframe::egui::{self, Align, CornerRadius, Layout, RichText, Sense, vec2};
use rusqlite::Connection;

use crate::shared::icons::{self, Icon};
use crate::shared::outcome::Outcome;
use crate::shared::task::{Status, Task};
use crate::shared::tasks;
use crate::shared::theme;
use crate::shared::widgets::{caption, nav_row};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Filter {
    All,
    Status(Status),
}

impl Filter {
    const OPTIONS: [Filter; 4] = [
        Filter::All,
        Filter::Status(Status::Todo),
        Filter::Status(Status::InProgress),
        Filter::Status(Status::Done),
    ];

    pub fn label(self) -> &'static str {
        match self {
            Filter::All => "All tasks",
            Filter::Status(s) => s.label(),
        }
    }

    fn icon(self) -> Icon {
        match self {
            Filter::All => Icon::All,
            Filter::Status(Status::Todo) => Icon::Todo,
            Filter::Status(Status::InProgress) => Icon::InProgress,
            Filter::Status(Status::Done) => Icon::Done,
        }
    }

    pub fn matches(self, task: &Task) -> bool {
        match self {
            Filter::All => true,
            Filter::Status(s) => task.status == s,
        }
    }
}

pub struct Filters {
    selected: Filter,
}

impl Filters {
    pub fn new() -> Self {
        Self {
            selected: Filter::All,
        }
    }

    pub fn selected(&self) -> Filter {
        self.selected
    }

    /// `active` is false while another page (e.g. settings) is showing, so no
    /// filter looks selected.
    pub fn show(
        &mut self,
        ui: &mut egui::Ui,
        conn: &Connection,
        tasks: &[Task],
        active: bool,
    ) -> Output {
        let p = theme::palette(ui.ctx());
        let mut output = Output::default();

        ui.add_space(4.0);
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            let (rect, _) = ui.allocate_exact_size(vec2(icons::SIZE + 6.0, icons::SIZE + 6.0), Sense::hover());
            icons::paint(ui.painter(), rect.center(), Icon::Logo, p.accent);
            ui.label(RichText::new("Tasks").size(22.0).strong());
        });
        ui.add_space(14.0);

        caption(ui, "LIBRARY");
        for filter in Filter::OPTIONS {
            let count = tasks.iter().filter(|t| filter.matches(t)).count();
            let selected = active && self.selected == filter;
            if nav_row(ui, filter.icon(), filter.label(), &count.to_string(), selected).clicked() {
                self.selected = filter;
                output.row_clicked = true;
            }
        }

        ui.add_space(18.0);
        let total = tasks.len();
        let done = tasks.iter().filter(|t| t.is_done()).count();
        let fraction = if total == 0 { 0.0 } else { done as f32 / total as f32 };
        caption(ui, "PROGRESS");
        ui.add(
            egui::ProgressBar::new(fraction)
                .fill(p.accent)
                .desired_height(8.0)
                .corner_radius(CornerRadius::same(4)),
        );
        caption(ui, &format!("{done} of {total} completed"));

        ui.with_layout(Layout::bottom_up(Align::Min), |ui| {
            if done > 0 && ui.button("Clear completed").clicked() {
                output.outcome = Some(tasks::clear_completed(conn).into());
            }
        });

        output
    }
}

/// What the sidebar reports back to the shell.
#[derive(Default)]
pub struct Output {
    pub outcome: Option<Outcome>,
    /// A filter row was clicked (even if it was already selected).
    pub row_clicked: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shared::task::Priority;

    fn task(status: Status) -> Task {
        Task {
            id: 1,
            title: "t".into(),
            notes: String::new(),
            priority: Priority::Medium,
            status,
            due: String::new(),
        }
    }

    #[test]
    fn filter_matches_by_status() {
        assert!(Filter::All.matches(&task(Status::Done)));
        assert!(Filter::Status(Status::Done).matches(&task(Status::Done)));
        assert!(!Filter::Status(Status::Done).matches(&task(Status::Todo)));
    }
}
