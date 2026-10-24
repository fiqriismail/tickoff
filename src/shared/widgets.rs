use eframe::egui::{
    Align2, Button, Color32, CornerRadius, CursorIcon, FontId, Response, RichText, Sense, Ui, vec2,
};

use super::icons::{self, Icon};
use super::theme;

/// A full-width sidebar entry with an accent-coloured icon and a right-aligned
/// `detail` (e.g. a count).
pub fn nav_row(ui: &mut Ui, icon: Icon, label: &str, detail: &str, selected: bool) -> Response {
    let p = theme::palette(ui.ctx());
    let (rect, response) = ui.allocate_exact_size(vec2(ui.available_width(), 36.0), Sense::click());
    let background = if selected {
        p.accent.gamma_multiply(0.18)
    } else if response.hovered() {
        p.hover
    } else {
        Color32::TRANSPARENT
    };
    let color = if selected { p.text } else { p.muted };

    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same(8), background);
    icons::paint(painter, rect.left_center() + vec2(12.0 + icons::SIZE / 2.0, 0.0), icon, p.accent);
    painter.text(
        rect.left_center() + vec2(12.0 + icons::SIZE + 10.0, 0.0),
        Align2::LEFT_CENTER,
        label,
        FontId::proportional(15.0),
        color,
    );
    painter.text(
        rect.right_center() - vec2(12.0, 0.0),
        Align2::RIGHT_CENTER,
        detail,
        FontId::proportional(13.0),
        p.muted,
    );
    response.on_hover_cursor(CursorIcon::PointingHand)
}

pub fn primary_button(ui: &mut Ui, text: &str) -> Response {
    let p = theme::palette(ui.ctx());
    ui.add(
        Button::new(RichText::new(text).strong().color(p.on_accent))
            .fill(p.accent)
            .min_size(vec2(80.0, 0.0)),
    )
    .on_hover_cursor(CursorIcon::PointingHand)
}

/// Small muted text used above form fields and section headings.
pub fn caption(ui: &mut Ui, text: &str) {
    let p = theme::palette(ui.ctx());
    ui.label(RichText::new(text).small().color(p.muted));
}
