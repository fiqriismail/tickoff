import SwiftUI

/// One task as a card: completion circle, title, note preview, status/priority pills and due label.
/// It reports what the user asked for through closures; the list turns those into store calls.
struct TaskCard: View {
    let task: Task
    let appearance: Appearance
    let setStatus: (Status) -> Void
    let edit: () -> Void
    let delete: () -> Void

    private var compact: Bool { appearance.compactCards }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StatusCircle(status: task.status, appearance: appearance) {
                setStatus(task.isDone ? .todo : .done)
            }

            VStack(alignment: .leading, spacing: compact ? 0 : 6) {
                if compact {
                    HStack(spacing: 8) {
                        title
                        meta
                    }
                } else {
                    title
                }
                if appearance.showNotes, let line = notePreview {
                    Text(line)
                        .font(appearance.font(0.9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !compact { meta }
            }
            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button("Edit", action: edit).help("Edit this task")
                Button("Delete", role: .destructive, action: delete).help("Delete this task")
            }
            .buttonStyle(.borderless)
            .font(appearance.font(0.9))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 16 : 22)
        .padding(.vertical, compact ? 9 : 20)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Edit…", action: edit)
            Menu("Change Status") {
                ForEach(Status.allCases, id: \.self) { status in
                    Button(status.label) { setStatus(status) }
                        .disabled(status == task.status)
                }
            }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var title: some View {
        Text(task.title)
            .font(appearance.font(1.1, weight: .bold))
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? .secondary : .primary)
            .lineLimit(1)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Button { setStatus(task.status.next) } label: {
                Pill(text: task.status.label, color: task.status.color, font: appearance.font(0.8, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Click to move to the next status")
            .accessibilityLabel("Status: \(task.status.label)")
            .accessibilityHint("Moves the task to \(task.status.next.label)")

            Pill(text: task.priority.label, color: task.priority.color, font: appearance.font(0.8, weight: .medium))

            if let due = DueLabel(for: task) {
                Label(due.text, systemImage: "calendar")
                    .font(appearance.font(0.85))
                    .foregroundStyle(due.tone.style)
            }
        }
    }

    /// Only the first line, so a long note never makes the cards uneven.
    private var notePreview: String? {
        let line = task.notes.split(separator: "\n", omittingEmptySubsequences: true).first
        return line.map(String.init)
    }
}

private struct StatusCircle: View {
    let status: Status
    let appearance: Appearance
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                switch status {
                case .done:
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                case .inProgress:
                    Circle().strokeBorder(.tint, lineWidth: 2)
                    Circle().fill(.tint).frame(width: 8, height: 8)
                case .todo:
                    Circle().strokeBorder(.secondary, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(status == .done ? "Mark as To do" : "Mark as Done")
        .accessibilityLabel(status == .done ? "Mark as To do" : "Mark as Done")
    }
}

private struct Pill: View {
    let text: String
    let color: Color
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

extension Status {
    fileprivate var color: Color {
        switch self {
        case .todo: .secondary
        case .inProgress: .accentColor
        case .done: .green
        }
    }
}

extension Priority {
    fileprivate var color: Color {
        switch self {
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

extension DueLabel.Tone {
    fileprivate var style: Color {
        switch self {
        case .overdue: .red
        case .today: .orange
        case .normal: .secondary
        }
    }
}
