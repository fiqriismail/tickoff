//! Feature: the settings page — appearance preferences, persisted in SQLite.

mod controls;
mod store;

use eframe::egui::{self, CornerRadius, Frame, Margin, RichText, Stroke};
use rusqlite::{Connection, Result};

use crate::shared::icons::Icon;
use crate::shared::outcome::Outcome;
use crate::shared::theme::{self, Appearance, ThemeMode, UiScale};
use crate::shared::widgets::{caption, nav_row};

use controls::{accent_picker, segmented, setting_row, toggle};

pub struct Settings {
    appearance: Appearance,
}

impl Settings {
    pub fn load(conn: &Connection) -> Result<Self> {
        Ok(Self {
            appearance: store::load(conn)?,
        })
    }

    pub fn appearance(&self) -> &Appearance {
        &self.appearance
    }

    /// The sidebar entry that opens this page.
    pub fn nav_row(&self, ui: &mut egui::Ui, active: bool) -> egui::Response {
        nav_row(ui, Icon::Settings, "Settings", "", active)
    }

    /// Draws the page. Changes are applied to the UI immediately and saved.
    pub fn show(&mut self, ui: &mut egui::Ui, conn: &Connection) -> Option<Outcome> {
        let p = theme::palette(ui.ctx());
        let mut changed = false;
        let mut reset = false;

        ui.heading("Settings");
        ui.label(RichText::new("Make the app feel like yours.").color(p.muted));
        ui.add_space(8.0);

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                Frame::new()
                    .fill(p.card)
                    .stroke(Stroke::new(1.0, p.border))
                    .corner_radius(CornerRadius::same(12))
                    .inner_margin(Margin::symmetric(20, 16))
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        caption(ui, "APPEARANCE");
                        let a = &mut self.appearance;

                        changed |= setting_row(
                            ui,
                            "Theme",
                            "Light, dark, or follow your system",
                            |ui| {
                                let options = ThemeMode::ALL.map(|m| (m, m.label()));
                                segmented(ui, &mut a.mode, &options)
                            },
                        );
                        ui.separator();
                        changed |= setting_row(
                            ui,
                            "Accent colour",
                            "Buttons, highlights and progress",
                            |ui| accent_picker(ui, &mut a.accent),
                        );
                        ui.separator();
                        changed |= setting_row(ui, "Text size", "Scales the whole interface", |ui| {
                            let options = UiScale::ALL.map(|s| (s, s.label()));
                            segmented(ui, &mut a.scale, &options)
                        });
                    });

                ui.add_space(6.0);
                Frame::new()
                    .fill(p.card)
                    .stroke(Stroke::new(1.0, p.border))
                    .corner_radius(CornerRadius::same(12))
                    .inner_margin(Margin::symmetric(20, 16))
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        caption(ui, "TASK LIST");
                        let a = &mut self.appearance;

                        changed |= setting_row(
                            ui,
                            "Compact cards",
                            "Tighter spacing so more tasks fit on screen",
                            |ui| toggle(ui, &mut a.compact_cards),
                        );
                        ui.separator();
                        changed |= setting_row(
                            ui,
                            "Show notes on cards",
                            "Preview the first line of a task's notes",
                            |ui| toggle(ui, &mut a.show_notes),
                        );
                    });

                ui.add_space(6.0);
                if ui.button("Reset to defaults").clicked() {
                    reset = true;
                }
            });

        if reset {
            self.appearance = Appearance::default();
            changed = true;
        }
        if !changed {
            return None;
        }

        theme::apply(ui.ctx(), &self.appearance);
        Some(store::save(conn, &self.appearance).into())
    }
}
