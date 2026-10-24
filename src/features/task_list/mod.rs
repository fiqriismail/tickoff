//! Feature: the task list — page header, search box and the task cards, plus
//! everything that happens *from* a card (toggle status, delete, request edit).

mod card;

use std::collections::HashMap;

use chrono::Local;
use eframe::egui::{
    self, Align, CornerRadius, CursorIcon, Frame, Id, Key, Layout, Margin, RichText, Sense, Stroke,
    TextEdit, UiBuilder, vec2,
};
use rusqlite::Connection;

use crate::shared::icons::{self, Icon};
use crate::shared::outcome::Outcome;
use crate::shared::task::{Status, Task};
use crate::shared::tasks::{self, TaskSet};
use crate::shared::theme::{self, Palette};

use card::Action;

/// What the list asks the shell to do.
pub enum Event {
    /// A card's edit button was pressed; the shell routes this to the edit dialog.
    Edit(Task),
    Outcome(Outcome),
}

/// Row positions are estimated until a card has been drawn once.
const ESTIMATED_CARD_HEIGHT: f32 = 100.0;

pub struct TaskList {
    search: String,
    focus_search: bool,
    /// Indices into the task set that pass the filter and the search, in display order.
    view: Vec<usize>,
    view_key: Option<(u64, Option<Status>, String)>,
    /// Measured card heights by task id; cards are only drawn while on screen.
    heights: HashMap<i64, f32>,
    heights_look: (bool, bool),
}

impl TaskList {
    pub fn new() -> Self {
        Self {
            search: String::new(),
            focus_search: false,
            view: Vec::new(),
            view_key: None,
            heights: HashMap::new(),
            heights_look: (false, false),
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

    /// Shows a card for each task in `tasks` with the given status (all when
    /// `None`) that matches the search box. Only the cards in view are drawn.
    pub fn show(
        &mut self,
        ui: &mut egui::Ui,
        conn: &Connection,
        tasks: &TaskSet,
        status: Option<Status>,
    ) -> Option<Event> {
        self.refresh_view(tasks, status);
        let p = theme::palette(ui.ctx());
        let look = theme::appearance(ui.ctx());
        let today = Local::now().date_naive();
        let mut action = None;

        if self.view.is_empty() {
            self.show_empty_state(ui, p, tasks.len());
            return None;
        }

        let look_key = (look.compact_cards, look.show_notes);
        if self.heights_look != look_key {
            self.heights.clear();
            self.heights_look = look_key;
        }
        if self.heights.len() > tasks.len() * 2 {
            self.heights.clear();
        }

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show_viewport(ui, |ui, viewport| {
                let gap = if look.compact_cards { 8.0 } else { 14.0 };
                ui.spacing_mut().item_spacing.y = gap;

                let estimate = if self.heights.is_empty() {
                    ESTIMATED_CARD_HEIGHT
                } else {
                    self.heights.values().sum::<f32>() / self.heights.len() as f32
                };

                let rows = self.view.len();
                let (mut first, mut end) = (rows, rows);
                let (mut first_y, mut end_y, mut y) = (0.0_f32, 0.0_f32, 0.0_f32);
                let mut last_row_height = 0.0;
                for (row, &index) in self.view.iter().enumerate() {
                    let h = self.heights.get(&tasks.items()[index].id).copied().unwrap_or(estimate) + gap;
                    if first == rows && y + h > viewport.min.y {
                        first = row;
                        first_y = y;
                    }
                    if first != rows && end == rows && y > viewport.max.y {
                        end = row;
                        end_y = y;
                    }
                    last_row_height = h;
                    y += h;
                }
                if first == rows {
                    first = rows - 1;
                    first_y = y - last_row_height;
                }
                if end == rows {
                    end_y = y;
                }

                ui.set_height((y - gap).max(0.0));
                let top = ui.max_rect().top() + first_y;
                let rect = egui::Rect::from_x_y_ranges(
                    ui.max_rect().x_range(),
                    top..=(ui.max_rect().top() + end_y),
                );
                ui.scope_builder(UiBuilder::new().max_rect(rect), |ui| {
                    ui.spacing_mut().item_spacing.y = gap;
                    for &index in &self.view[first..end] {
                        let task = &tasks.items()[index];
                        let drawn = ui.push_id(task.id, |ui| card::show(ui, p, look, task, today));
                        self.heights.insert(task.id, drawn.response.rect.height());
                        if let Some(a) = drawn.inner {
                            action = Some(a);
                        }
                    }
                });
            });

        match action? {
            Action::Edit(task) => Some(Event::Edit(task)),
            Action::SetStatus(id, status) => {
                Some(Event::Outcome(tasks::set_status(conn, id, status).into()))
            }
            Action::Delete(id) => Some(Event::Outcome(tasks::delete(conn, id).into())),
        }
    }

    /// Recomputes which tasks are listed, but only when the data, filter or search changed.
    fn refresh_view(&mut self, tasks: &TaskSet, status: Option<Status>) {
        let query = self.search.trim().to_lowercase();
        let key = (tasks.revision(), status, query);
        if self.view_key.as_ref() == Some(&key) {
            return;
        }
        self.view = tasks
            .items()
            .iter()
            .enumerate()
            .filter(|(i, t)| status.is_none_or(|s| t.status == s) && tasks.matches(*i, &key.2))
            .map(|(i, _)| i)
            .collect();
        self.view_key = Some(key);
    }

    fn show_empty_state(&self, ui: &mut egui::Ui, p: Palette, total: usize) {
        ui.add_space(60.0);
        ui.vertical_centered(|ui| {
            if !self.search.trim().is_empty() {
                ui.label(
                    RichText::new(format!("No results for “{}”", self.search.trim()))
                        .size(16.0)
                        .strong(),
                );
                ui.label(RichText::new("Check the spelling or try a different search.").color(p.muted));
            } else {
                ui.label(RichText::new("🎉").size(40.0));
                let message = if total == 0 {
                    "No tasks yet — add your first one above."
                } else {
                    "Nothing here yet."
                };
                ui.label(RichText::new(message).color(p.muted));
            }
        });
    }
}
