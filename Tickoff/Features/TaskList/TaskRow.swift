import SwiftUI

/// One task as a plain list row: completion circle, title, one-line note and a single line of
/// metadata. Status and priority are always words in secondary text; colour only tints their symbols. It has no buttons
/// of its own besides the circle: edit, status and delete live in the context menu and menu bar.
struct TaskRow: View {
    let task: Task
    let appearance: Appearance
    /// The task's project, given only when the list spans all projects (otherwise it is implied).
    let project: Project?
    let setStatus: (Status) -> Void

    private var compact: Bool { appearance.compactCards }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusCircle(status: task.status) {
                setStatus(task.isDone ? .todo : .done)
            }

            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !compact { meta }
            }
        }
        .padding(.vertical, compact ? 1 : 4)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(task.title)
            .font(.body)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? .secondary : .primary)
            .lineLimit(1)
    }

    private var meta: some View {
        HStack(spacing: 10) {
            Text(task.status.label)
            if let project { projectLabel(project) }
            // Text stays secondary so it keeps its contrast; the symbol carries the colour.
            Label {
                Text("\(task.priority.label) priority")
            } icon: {
                Image(systemName: "flag.fill").foregroundStyle(task.priority.color)
            }
            if let due = DueLabel(for: task) {
                Label {
                    Text(due.text)
                } icon: {
                    Image(systemName: "calendar").foregroundStyle(due.tone.style)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Colour dot and name; muted when the project is archived.
    private func projectLabel(_ project: Project) -> some View {
        HStack(spacing: 5) {
            Circle().fill(project.colour.color).frame(width: 7, height: 7)
            Text(project.name)
        }
        .opacity(project.archived ? 0.6 : 1)
        .accessibilityLabel("Project: \(project.name)\(project.archived ? ", archived" : "")")
    }

    /// Only the first line, so a long note never makes the rows uneven.
    private var notePreview: String? {
        let line = task.notes.split(separator: "\n", omittingEmptySubsequences: true).first
        return line.map(String.init)
    }
}

private struct StatusCircle: View {
    let status: Status
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                switch status {
                case .done:
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                case .inProgress:
                    Circle().strokeBorder(.tint, lineWidth: 2)
                    Circle().fill(.tint).frame(width: 7, height: 7)
                case .todo:
                    Circle().strokeBorder(.secondary, lineWidth: 2)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(status == .done ? "Mark as To Do" : "Mark as Done")
        .accessibilityLabel(status == .done ? "Mark as To Do" : "Mark as Done")
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
