//! Small vector icons drawn with the painter, so they stay crisp, follow the
//! accent colour, and don't depend on which glyphs the UI font happens to have.

use std::f32::consts::{FRAC_PI_2, FRAC_PI_4, TAU};

use eframe::egui::{Color32, Painter, Pos2, Shape, Stroke, Vec2, vec2};

/// Icons are drawn inside a square of this side length.
pub const SIZE: f32 = 18.0;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Icon {
    /// Three list lines.
    All,
    /// Empty circle.
    Todo,
    /// Circle with the right half filled.
    InProgress,
    /// Circle with a check mark.
    Done,
    Settings,
    /// A bold check mark, used for the app title.
    Logo,
    /// Magnifying glass.
    Search,
    /// Filled circle with a cross, for clearing a text field.
    Clear,
}

pub fn paint(painter: &Painter, center: Pos2, icon: Icon, color: Color32) {
    let line = Stroke::new(1.8, color);
    let at = |x: f32, y: f32| center + vec2(x, y);
    const R: f32 = 7.0;

    match icon {
        Icon::All => {
            painter.line_segment([at(-7.0, -5.0), at(7.0, -5.0)], line);
            painter.line_segment([at(-7.0, 0.0), at(7.0, 0.0)], line);
            painter.line_segment([at(-7.0, 5.0), at(2.0, 5.0)], line);
        }
        Icon::Todo => {
            painter.circle_stroke(center, R, line);
        }
        Icon::InProgress => {
            painter.circle_stroke(center, R, line);
            let half_disc: Vec<Pos2> = (0..=16)
                .map(|i| {
                    let angle = -FRAC_PI_2 + TAU / 2.0 * (i as f32 / 16.0);
                    center + Vec2::angled(angle) * (R - 2.5)
                })
                .collect();
            painter.add(Shape::convex_polygon(half_disc, color, Stroke::NONE));
        }
        Icon::Done => {
            painter.circle_stroke(center, R, line);
            painter.line(vec![at(-3.0, 0.5), at(-0.8, 2.8), at(3.2, -2.4)], line);
        }
        Icon::Settings => {
            painter.circle_stroke(center, 5.0, line);
            for i in 0..8 {
                let direction = Vec2::angled(FRAC_PI_4 * i as f32);
                painter.line_segment([center + direction * 5.8, center + direction * 8.2], line);
            }
            painter.circle_filled(center, 1.6, color);
        }
        Icon::Logo => {
            let bold = Stroke::new(3.0, color);
            painter.line(vec![at(-7.0, 1.0), at(-2.5, 5.5), at(7.5, -5.5)], bold);
        }
        Icon::Search => {
            painter.circle_stroke(at(-1.5, -1.5), 5.0, line);
            painter.line_segment([at(2.2, 2.2), at(7.0, 7.0)], line);
        }
        Icon::Clear => {
            painter.circle_filled(center, R, color);
            let cross = Stroke::new(1.6, Color32::from_black_alpha(190));
            painter.line_segment([at(-2.6, -2.6), at(2.6, 2.6)], cross);
            painter.line_segment([at(-2.6, 2.6), at(2.6, -2.6)], cross);
        }
    }
}
