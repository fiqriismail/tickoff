use rusqlite::{Connection, Result};

use crate::shared::theme::{Accent, Appearance, ThemeMode, UiScale};

/// Missing or unrecognised values fall back to the defaults, so a fresh or
/// older database never prevents the app from starting.
pub fn load(conn: &Connection) -> Result<Appearance> {
    let mut appearance = Appearance::default();
    let mut stmt = conn.prepare("SELECT key, value FROM settings")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    for row in rows {
        let (key, value) = row?;
        match key.as_str() {
            "theme_mode" => {
                appearance.mode = ThemeMode::from_key(&value).unwrap_or(appearance.mode)
            }
            "accent" => appearance.accent = Accent::from_key(&value).unwrap_or(appearance.accent),
            "ui_scale" => appearance.scale = UiScale::from_key(&value).unwrap_or(appearance.scale),
            "compact_cards" => appearance.compact_cards = value == "true",
            "show_notes" => appearance.show_notes = value == "true",
            _ => {}
        }
    }
    Ok(appearance)
}

pub fn save(conn: &Connection, appearance: &Appearance) -> Result<()> {
    let entries = [
        ("theme_mode", appearance.mode.key()),
        ("accent", appearance.accent.key()),
        ("ui_scale", appearance.scale.key()),
        ("compact_cards", bool_key(appearance.compact_cards)),
        ("show_notes", bool_key(appearance.show_notes)),
    ];
    // One transaction, so a failure never leaves a half-applied set of settings.
    let tx = conn.unchecked_transaction()?;
    for (key, value) in entries {
        tx.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )?;
    }
    tx.commit()
}

fn bool_key(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shared::db;

    #[test]
    fn a_fresh_database_loads_the_defaults() {
        let conn = db::open_in_memory().unwrap();
        assert_eq!(load(&conn).unwrap(), Appearance::default());
    }

    #[test]
    fn saved_settings_are_loaded_back_and_can_be_overwritten() {
        let conn = db::open_in_memory().unwrap();
        let custom = Appearance {
            mode: ThemeMode::Light,
            accent: Accent::Teal,
            scale: UiScale::Large,
            compact_cards: true,
            show_notes: false,
        };
        save(&conn, &custom).unwrap();
        assert_eq!(load(&conn).unwrap(), custom);

        save(&conn, &Appearance::default()).unwrap();
        assert_eq!(load(&conn).unwrap(), Appearance::default());
    }

    #[test]
    fn a_failed_save_leaves_the_old_settings_untouched() {
        let conn = db::open_in_memory().unwrap();
        save(&conn, &Appearance::default()).unwrap();
        conn.execute_batch(
            "CREATE TRIGGER reject_scale BEFORE UPDATE ON settings
             WHEN NEW.key = 'ui_scale' BEGIN SELECT RAISE(ABORT, 'nope'); END;",
        )
        .unwrap();

        let custom = Appearance {
            mode: ThemeMode::Light,
            accent: Accent::Teal,
            scale: UiScale::Large,
            compact_cards: true,
            show_notes: false,
        };
        assert!(save(&conn, &custom).is_err());
        assert_eq!(load(&conn).unwrap(), Appearance::default());
    }

    #[test]
    fn unknown_values_are_ignored() {
        let conn = db::open_in_memory().unwrap();
        conn.execute_batch(
            "INSERT INTO settings VALUES ('theme_mode', 'neon'), ('mystery', 'x'), ('accent', 'rose');",
        )
        .unwrap();

        let loaded = load(&conn).unwrap();
        assert_eq!(loaded.mode, Appearance::default().mode);
        assert_eq!(loaded.accent, Accent::Rose);
    }
}
