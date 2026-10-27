import Foundation

/// How a task's due date reads on its card, relative to today.
struct DueLabel: Equatable {
    enum Tone: Equatable { case overdue, today, normal }

    var text: String
    var tone: Tone

    /// `nil` when the task has no (valid) due date. Finished tasks show the plain date, never overdue.
    init?(
        for task: Task, today: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        guard let date = task.dueDate(calendar: calendar) else { return nil }
        let short = Self.shortDate(date, calendar: calendar, locale: locale)
        if task.isDone {
            self.init(text: short, tone: .normal)
            return
        }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: today), to: date
            ).day ?? 0
        switch days {
        case ..<0: self.init(text: "Overdue · \(short)", tone: .overdue)
        case 0: self.init(text: "Today", tone: .today)
        case 1: self.init(text: "Tomorrow", tone: .normal)
        default: self.init(text: short, tone: .normal)
        }
    }

    init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    private static func shortDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}
