import GRDB

/// The one place that talks SQL about the `settings` table.
struct SettingsStore: Sendable {
    let database: AppDatabase

    /// Missing or unrecognised values fall back to the defaults, so a fresh or older database
    /// never prevents the app from starting.
    func load() throws -> Appearance {
        let rows = try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
        }

        var appearance = Appearance.default
        for row in rows {
            guard let key = String.fromDatabaseValue(row[0]),
                let value = String.fromDatabaseValue(row[1])
            else { continue }
            switch key {
            case "theme_mode": appearance.mode = ThemeMode(key: value) ?? appearance.mode
            case "accent": appearance.accent = Accent(key: value) ?? appearance.accent
            case "ui_scale": appearance.scale = UiScale(key: value) ?? appearance.scale
            case "compact_cards": appearance.compactCards = value == "true"
            case "show_notes": appearance.showNotes = value == "true"
            default: break
            }
        }
        return appearance
    }

    /// `write` is one transaction, so a failure never leaves a half-applied set of settings.
    func save(_ appearance: Appearance) throws {
        let entries: [(String, String)] = [
            ("theme_mode", appearance.mode.key),
            ("accent", appearance.accent.key),
            ("ui_scale", appearance.scale.key),
            ("compact_cards", Self.boolKey(appearance.compactCards)),
            ("show_notes", Self.boolKey(appearance.showNotes)),
        ]
        try database.queue.write { db in
            for (key, value) in entries {
                try db.execute(
                    sql: """
                        INSERT INTO settings (key, value) VALUES (?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """,
                    arguments: [key, value])
            }
        }
    }

    private static func boolKey(_ value: Bool) -> String { value ? "true" : "false" }
}
