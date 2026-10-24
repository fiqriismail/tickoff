//! Look and feel: user-selectable appearance preferences, the colour palette
//! derived from them, and the egui style setup.
//!
//! Features read colours with `theme::palette(ctx)` instead of hard-coding them,
//! so they follow the active light/dark theme and accent colour automatically.

use eframe::egui::{
    self, Color32, CornerRadius, FontId, Id, Margin, Stroke, TextStyle, Theme, ThemePreference,
    vec2,
};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ThemeMode {
    Light,
    Dark,
    System,
}

impl ThemeMode {
    pub const ALL: [ThemeMode; 3] = [ThemeMode::Light, ThemeMode::Dark, ThemeMode::System];

    pub fn label(self) -> &'static str {
        match self {
            ThemeMode::Light => "Light",
            ThemeMode::Dark => "Dark",
            ThemeMode::System => "System",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            ThemeMode::Light => "light",
            ThemeMode::Dark => "dark",
            ThemeMode::System => "system",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|m| m.key() == key)
    }

    fn preference(self) -> ThemePreference {
        match self {
            ThemeMode::Light => ThemePreference::Light,
            ThemeMode::Dark => ThemePreference::Dark,
            ThemeMode::System => ThemePreference::System,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Accent {
    Indigo,
    Violet,
    Teal,
    Rose,
    Orange,
}

impl Accent {
    pub const ALL: [Accent; 5] = [
        Accent::Indigo,
        Accent::Violet,
        Accent::Teal,
        Accent::Rose,
        Accent::Orange,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Accent::Indigo => "Indigo",
            Accent::Violet => "Violet",
            Accent::Teal => "Teal",
            Accent::Rose => "Rose",
            Accent::Orange => "Orange",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Accent::Indigo => "indigo",
            Accent::Violet => "violet",
            Accent::Teal => "teal",
            Accent::Rose => "rose",
            Accent::Orange => "orange",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|a| a.key() == key)
    }

    /// Bright variants on dark backgrounds, deeper variants on light ones.
    pub fn color(self, theme: Theme) -> Color32 {
        let (dark, light) = match self {
            Accent::Indigo => ((0x7C, 0x83, 0xFF), (0x50, 0x58, 0xE6)),
            Accent::Violet => ((0xA7, 0x8B, 0xFA), (0x7C, 0x3A, 0xED)),
            Accent::Teal => ((0x2D, 0xD4, 0xBF), (0x0D, 0x94, 0x88)),
            Accent::Rose => ((0xFB, 0x71, 0x85), (0xE1, 0x1D, 0x48)),
            Accent::Orange => ((0xFB, 0x92, 0x3C), (0xEA, 0x58, 0x0C)),
        };
        let (r, g, b) = match theme {
            Theme::Dark => dark,
            Theme::Light => light,
        };
        Color32::from_rgb(r, g, b)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum UiScale {
    Small,
    Default,
    Large,
}

impl UiScale {
    pub const ALL: [UiScale; 3] = [UiScale::Small, UiScale::Default, UiScale::Large];

    pub fn label(self) -> &'static str {
        match self {
            UiScale::Small => "Small",
            UiScale::Default => "Default",
            UiScale::Large => "Large",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            UiScale::Small => "small",
            UiScale::Default => "default",
            UiScale::Large => "large",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.key() == key)
    }

    fn zoom_factor(self) -> f32 {
        match self {
            UiScale::Small => 0.9,
            UiScale::Default => 1.0,
            UiScale::Large => 1.15,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Appearance {
    pub mode: ThemeMode,
    pub accent: Accent,
    pub scale: UiScale,
    pub compact_cards: bool,
    pub show_notes: bool,
}

impl Default for Appearance {
    fn default() -> Self {
        Self {
            mode: ThemeMode::System,
            accent: Accent::Indigo,
            scale: UiScale::Default,
            compact_cards: false,
            show_notes: true,
        }
    }
}

#[derive(Clone, Copy)]
pub struct Palette {
    pub bg: Color32,
    pub sidebar: Color32,
    pub card: Color32,
    pub border: Color32,
    pub input: Color32,
    pub hover: Color32,
    pub text: Color32,
    pub muted: Color32,
    pub accent: Color32,
    /// Readable text colour on top of `accent`.
    pub on_accent: Color32,
    pub green: Color32,
    pub amber: Color32,
    pub red: Color32,
    pub blue: Color32,
}

impl Palette {
    pub fn new(theme: Theme, accent: Accent) -> Self {
        let accent = accent.color(theme);
        let dark_text = Color32::from_rgb(0x10, 0x12, 0x1A);
        let on_accent = if contrast(accent, dark_text) > contrast(accent, Color32::WHITE) {
            dark_text
        } else {
            Color32::WHITE
        };
        match theme {
            Theme::Dark => Self {
                bg: rgb(0x0E1016),
                sidebar: rgb(0x12141C),
                card: rgb(0x181B25),
                border: rgb(0x262A38),
                input: rgb(0x1B1F2B),
                hover: rgb(0x24293A),
                text: rgb(0xE6E8EF),
                muted: rgb(0x8A90A2),
                accent,
                on_accent,
                green: rgb(0x4ADE80),
                amber: rgb(0xFBBF24),
                red: rgb(0xF87171),
                blue: rgb(0x60A5FA),
            },
            Theme::Light => Self {
                bg: rgb(0xF4F5FA),
                sidebar: rgb(0xFFFFFF),
                card: rgb(0xFFFFFF),
                border: rgb(0xE1E4EE),
                input: rgb(0xF0F2F8),
                hover: rgb(0xE6E9F3),
                text: rgb(0x1B1E2B),
                muted: rgb(0x687087),
                accent,
                on_accent,
                green: rgb(0x16A34A),
                amber: rgb(0xD97706),
                red: rgb(0xDC2626),
                blue: rgb(0x2563EB),
            },
        }
    }
}

fn rgb(hex: u32) -> Color32 {
    Color32::from_rgb((hex >> 16) as u8, (hex >> 8) as u8, hex as u8)
}

/// WCAG contrast ratio between two colours (1.0 = identical, 21.0 = black on white).
fn contrast(a: Color32, b: Color32) -> f32 {
    let (la, lb) = (luminance(a), luminance(b));
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

/// Approximate relative luminance in `0.0..=1.0`.
fn luminance(c: Color32) -> f32 {
    let channel = |v: u8| {
        let v = v as f32 / 255.0;
        if v <= 0.03928 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * channel(c.r()) + 0.7152 * channel(c.g()) + 0.0722 * channel(c.b())
}

fn appearance_id() -> Id {
    Id::unique("hello_gui::appearance")
}

/// The palette for whichever theme (light/dark) is active right now.
pub fn palette(ctx: &egui::Context) -> Palette {
    Palette::new(ctx.theme(), appearance(ctx).accent)
}

pub fn appearance(ctx: &egui::Context) -> Appearance {
    ctx.data(|d| d.get_temp(appearance_id()))
        .unwrap_or_default()
}

/// Installs `appearance` into the context: theme preference, styles for both
/// themes, zoom, and the value returned by [`appearance`].
pub fn apply(ctx: &egui::Context, appearance: &Appearance) {
    ctx.data_mut(|d| d.insert_temp(appearance_id(), *appearance));
    ctx.set_theme(appearance.mode.preference());
    ctx.set_zoom_factor(appearance.scale.zoom_factor());

    for theme in [Theme::Dark, Theme::Light] {
        ctx.set_style_of(theme, style_for(theme, appearance.accent));
    }
}

fn style_for(theme: Theme, accent: Accent) -> egui::Style {
    let p = Palette::new(theme, accent);
    let mut style = match theme {
        Theme::Dark => egui::Style {
            visuals: egui::Visuals::dark(),
            ..Default::default()
        },
        Theme::Light => egui::Style {
            visuals: egui::Visuals::light(),
            ..Default::default()
        },
    };

    let v = &mut style.visuals;
    v.panel_fill = p.bg;
    v.window_fill = p.card;
    v.extreme_bg_color = p.input;
    v.faint_bg_color = p.card;
    v.override_text_color = Some(p.text);
    v.window_corner_radius = CornerRadius::same(14);
    v.window_stroke = Stroke::new(1.0, p.border);
    v.selection.bg_fill = p.accent.gamma_multiply(0.45);
    v.selection.stroke = Stroke::new(1.0, p.accent);
    v.hyperlink_color = p.accent;

    let radius = CornerRadius::same(8);
    for w in [
        &mut v.widgets.noninteractive,
        &mut v.widgets.inactive,
        &mut v.widgets.hovered,
        &mut v.widgets.active,
        &mut v.widgets.open,
    ] {
        w.corner_radius = radius;
    }
    v.widgets.noninteractive.bg_stroke = Stroke::new(1.0, p.border);
    v.widgets.noninteractive.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.inactive.bg_fill = p.input;
    v.widgets.inactive.weak_bg_fill = p.input;
    v.widgets.inactive.bg_stroke = Stroke::new(1.0, p.border);
    v.widgets.inactive.fg_stroke = Stroke::new(1.0, p.text);
    v.widgets.hovered.bg_fill = p.hover;
    v.widgets.hovered.weak_bg_fill = p.hover;
    v.widgets.hovered.bg_stroke = Stroke::new(1.0, p.accent.gamma_multiply(0.7));
    v.widgets.hovered.fg_stroke = Stroke::new(1.5, p.text);
    v.widgets.active.bg_fill = p.accent.gamma_multiply(0.5);
    v.widgets.active.weak_bg_fill = p.accent.gamma_multiply(0.5);
    v.widgets.active.fg_stroke = Stroke::new(2.0, p.text);

    style.spacing.item_spacing = vec2(10.0, 10.0);
    style.spacing.button_padding = vec2(12.0, 7.0);
    style.spacing.window_margin = Margin::same(20);

    style
        .text_styles
        .insert(TextStyle::Body, FontId::proportional(15.0));
    style
        .text_styles
        .insert(TextStyle::Button, FontId::proportional(15.0));
    style
        .text_styles
        .insert(TextStyle::Small, FontId::proportional(12.5));
    style
        .text_styles
        .insert(TextStyle::Heading, FontId::proportional(28.0));
    style
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_roundtrip_for_every_option() {
        for m in ThemeMode::ALL {
            assert_eq!(ThemeMode::from_key(m.key()), Some(m));
        }
        for a in Accent::ALL {
            assert_eq!(Accent::from_key(a.key()), Some(a));
        }
        for s in UiScale::ALL {
            assert_eq!(UiScale::from_key(s.key()), Some(s));
        }
        assert_eq!(ThemeMode::from_key("nonsense"), None);
    }

    #[test]
    fn text_on_accent_stays_readable() {
        for theme in [Theme::Dark, Theme::Light] {
            for accent in Accent::ALL {
                let p = Palette::new(theme, accent);
                let ratio = contrast(p.on_accent, p.accent);
                assert!(
                    ratio >= 3.0,
                    "{accent:?} on {theme:?} has contrast {ratio:.2}"
                );
            }
        }
    }
}
