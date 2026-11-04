import SwiftUI

/// A project's Today page: daily checks and counters, not ordinary tasks or task filters.
struct DailyGoalsView: View {
    let project: Project
    let model: DailyGoalsModel
    let report: (Outcome) -> Void
    let newGoalRequest: Int
    @State private var editor: GoalEditor?
    @State private var removing: GoalDay?
    @State private var selection: DailyGoal.ID?

    private var rows: [GoalDay] { model.rows[project.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Today").font(.title3)
                Spacer()
                Button("New Goal", systemImage: "plus") { editor = GoalEditor(goal: nil) }
            }
            .padding(16)
            if rows.isEmpty {
                ContentUnavailableView(
                    "No daily goals yet", systemImage: "target",
                    description: Text("Add a daily check-off or a counter to get started."))
                    .frame(maxHeight: .infinity)
            } else {
                List(rows, selection: $selection) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.body).lineLimit(1).help(row.name)
                            if row.hasPendingChanges {
                                Text("Changes scheduled for tomorrow")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if row.tracking == .checkOff {
                            Toggle("Completed today", isOn: Binding(
                                get: { row.isComplete },
                                set: { _ in change(row, increment: true) }))
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Complete \(row.name) today")
                        } else {
                            if row.isComplete {
                                Label("Completed", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                change(row, increment: false)
                            } label: {
                                Image(systemName: "minus").frame(width: 16, height: 16)
                            }
                            .buttonStyle(.bordered)
                            .disabled(row.value == 0)
                            .accessibilityLabel("Decrease \(row.name)")
                            Text("\(row.value) / \(row.target)")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .fixedSize()
                                .accessibilityLabel("\(row.value) of \(row.target) completed today")
                            Button {
                                change(row, increment: true)
                            } label: {
                                Image(systemName: "plus").frame(width: 16, height: 16)
                            }
                            .buttonStyle(.bordered)
                            .disabled(row.value == Int.max)
                            .accessibilityLabel("Increase \(row.name)")
                        }
                        Menu {
                            Button("Edit…") { editor = GoalEditor(goal: row.goal) }
                            Button("Remove…", role: .destructive) { removing = row }
                        } label: { Label("Goal Actions", systemImage: "ellipsis.circle") }
                        .labelStyle(.iconOnly)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Actions for \(row.name)")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 12)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle("Today · \(model.badges[project.id] ?? "0/0") completed")
        .focusedSceneValue(\.taskActions, nil)
        .focusedSceneValue(\.goalActions, selectedActions)
        .sheet(item: $editor) { item in
            GoalEditorView(
                projectID: project.id, goal: item.goal, store: model.store, finish: report)
        }
        .confirmationDialog(
            "Remove “\(removing?.name ?? "")”?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { row in
            Button("Remove Goal", role: .destructive) {
                report(Outcome.run { try model.store.remove(id: row.id) })
            }
        } message: { _ in
            Text("It will no longer appear in Today. Past progress will be kept.")
        }
        .onChange(of: newGoalRequest) { editor = GoalEditor(goal: nil) }
    }

    private func change(_ row: GoalDay, increment: Bool) {
        report(Outcome.run { try model.store.changeProgress(id: row.id, increment: increment) })
    }

    private var selectedActions: GoalActions? {
        guard let row = rows.first(where: { $0.id == selection }) else { return nil }
        return GoalActions(
            edit: { editor = GoalEditor(goal: row.goal) },
            remove: { removing = row },
            increase: { change(row, increment: true) },
            decrease: row.tracking == .counter && row.value > 0
                ? { change(row, increment: false) } : nil,
            increaseLabel: row.tracking == .checkOff ? "Toggle Completion" : "Increase Progress")
    }
}

/// Identifies both new and existing goal editor presentations.
private struct GoalEditor: Identifiable {
    let goal: DailyGoal?
    var id: Int64 { goal?.id ?? 0 }
}
