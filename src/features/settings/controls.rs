use eframe::egui::{
    self, Align, Button, Color32, CornerRadius, Frame, Layout, Margin, RichText, Sense, Stroke, vec2,
};

use crate::shared::theme::{self, Accent};

/// A pill-shaped single-choice selector. Returns true when the value changed.
pub fn segmented<T: Copy + PartialEq>(
    ui: &mut egui::Ui,
    value: &mut T,
    options: &[(T, &str)],
) -> bool {
    let p = theme::palette(ui.ctx());
    let mut changed = false;

    Frame::new()
        .fill(p.input)
        .stroke(Stroke::new(1.0, p.border))
        .corner_radius(CornerRadius::same(9))
        .inner_margin(Margin::same(3))
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 2.0;
                // `setting_row` lays controls out right-to-left, so iterate in reverse to read left-to-right.
                for (option, label) in options.iter().rev() {
                    let selected = *value == *option;
                    let text = if selected {
                        RichText::new(*label).strong().color(p.on_accent)
                    } else {
                        RichText::new(*label).color(p.muted)
                    };
                    let button = Button::new(text)
                        .fill(if selected { p.accent } else { Color32::TRANSPARENT })
                        .stroke(Stroke::NONE)
                        .corner_radius(CornerRadius::same(6))
                        .min_size(vec2(66.0, 0.0));
                    if ui.add(button).clicked() && !selected {
                        *value = *option;
                        changed = true;
                    }
                }
            });
        });

    changed
}

/// A row of colour dots. Returns true when the selection changed.
pub fn accent_picker(ui: &mut egui::Ui, value: &mut Accent) -> bool {
    let p = theme::palette(ui.ctx());
    let theme = ui.ctx().theme();
    let mut changed = false;

    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 10.0;
        // Reversed for the same reason as in `segmented`.
        for accent in Accent::ALL.into_iter().rev() {
            let (rect, response) = ui.allocate_exact_size(vec2(28.0, 28.0), Sense::click());
            let painter = ui.painter();
            painter.circle_filled(rect.center(), 10.0, accent.color(theme));
            if *value == accent {
                painter.circle_stroke(rect.center(), 13.0, Stroke::new(2.0, p.text));
            } else if response.hovered() {
                painter.circle_stroke(rect.center(), 13.0, Stroke::new(1.0, p.muted));
            }

            let response = response
                .on_hover_text(accent.label())
                .on_hover_cursor(egui::CursorIcon::PointingHand);
            if response.clicked() && *value != accent {
                *value = accent;
                changed = true;
            }
        }
    });

    changed
}

/// An animated on/off switch. Returns true when toggled.
pub fn toggle(ui: &mut egui::Ui, on: &mut bool) -> bool {
    let p = theme::palette(ui.ctx());
    let (rect, mut response) = ui.allocate_exact_size(vec2(44.0, 24.0), Sense::click());
    if response.clicked() {
        *on = !*on;
        response.mark_changed();
    }

    let t = ui.ctx().animate_bool_responsive(response.id, *on);
    let track_off = p.muted.gamma_multiply(0.35);
    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same(12), track_off.lerp_to_gamma(p.accent, t));
    let knob_x = egui::lerp((rect.left() + 12.0)..=(rect.right() - 12.0), t);
    painter.circle_filled(egui::pos2(knob_x, rect.center().y), 9.0, Color32::WHITE);

    let changed = response.changed();
    response.on_hover_cursor(egui::CursorIcon::PointingHand);
    changed
}

/// One labelled setting: title and description on the left, `control` on the
/// right. Returns whatever the control returns (true when it changed).
pub fn setting_row(
    ui: &mut egui::Ui,
    title: &str,
    description: &str,
    control: impl FnOnce(&mut egui::Ui) -> bool,
) -> bool {
    let p = theme::palette(ui.ctx());
    let mut changed = false;

    ui.horizontal(|ui| {
        ui.vertical(|ui| {
            ui.spacing_mut().item_spacing.y = 2.0;
            ui.label(RichText::new(title).strong());
            ui.label(RichText::new(description).small().color(p.muted));
        });
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            changed = control(ui);
        });
    });

    changed
}
