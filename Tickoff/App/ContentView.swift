import SwiftUI

/// The shell layout: a hideable, resizable sidebar of filters and the task area as the detail.
/// It only routes; the sidebar's selection lives here so features never import each other.
struct ContentView: View {
    let model: AppModel
    @State private var filter: Filter = .all
    @State private var editing: Task?
    @State private var projectSheet: ProjectSheet?
    /// Bumped by menu commands; the features focus their field when it changes.
    @State private var newTaskRequest = 0
    @State private var findRequest = 0
    @State private var clearRequest = 0
    @State private var newGoalRequest = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            FiltersView(
                tasks: model.tasks,
                scope: Binding(get: { model.scope }, set: { model.select($0) }),
                filter: $filter,
                showsTaskFilters: model.selectedDailyProject == nil,
                projects: {
                    ProjectsSection(
                        projects: model.visibleProjects, tasks: model.tasks,
                        store: model.projectStore, report: model.handle,
                        edit: { projectSheet = ProjectSheet(project: $0) },
                        goalBadges: model.dailyGoals.badges)
                }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Group {
                if let project = model.selectedDailyProject {
                    DailyGoalsView(
                        project: project, model: model.dailyGoals, report: model.handle,
                        newGoalRequest: newGoalRequest)
                        .id(project.id)
                } else {
                    TaskListView(
                        tasks: model.tasks, filter: filter, scope: model.scope, projects: model.projects,
                        appearance: model.settings.appearance,
                        store: model.taskStore, report: model.handle,
                        searchRequest: findRequest, clearRequest: clearRequest,
                        updateAppearance: model.settings.update,
                        edit: { editing = $0 },
                        accessory: {
                            AddTaskBar(
                                store: model.taskStore, projects: model.taskProjects,
                                recentProjectIDs: model.recentProjectIDs,
                                defaultProjectID: model.newTaskProjectID,
                                offersProjectChoice: model.scope == .all, report: model.handle,
                                used: model.projectUsed, focusRequest: newTaskRequest)
                        }
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message, dismiss: model.dismissError)
                }
            }
        }
        .sheet(item: $editing) { task in
            EditTaskView(
                task: task, store: model.taskStore, projects: model.projectChoices(for: task),
                finish: model.handle)
        }
        .sheet(item: $projectSheet) { sheet in
            ProjectEditorView(
                project: sheet.project, store: model.projectStore, finish: model.handle)
        }
        .focusedSceneValue(
            \.appActions,
            AppActions(
                newTask: { newTaskRequest += 1 },
                newProject: { projectSheet = ProjectSheet(project: nil) },
                find: { findRequest += 1 },
                clearCompleted: { clearRequest += 1 },
                canClearCompleted: model.selectedDailyProject == nil
                    && model.tasks.count(.done, project: model.scope.projectID) > 0,
                showNotes: model.settings.appearance.showNotes,
                compactRows: model.settings.appearance.compactCards,
                setShowNotes: { value in model.settings.update { $0.showNotes = value } },
                setCompactRows: { value in model.settings.update { $0.compactCards = value } },
                showsTasks: model.selectedDailyProject == nil,
                newGoal: model.selectedDailyProject == nil ? nil : { newGoalRequest += 1 })
        )
        .task {
            await model.dailyGoals.watchDayChanges(report: model.report)
        }
        .onChange(of: scenePhase) { if scenePhase == .active { refreshDailyGoals() } }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func refreshDailyGoals() {
        do {
            try model.dailyGoals.refreshIfNeeded()
        } catch {
            model.report(.failed(error.localizedDescription))
        }
    }
}

/// What the project editor sheet is for; `project` is `nil` when creating.
private struct ProjectSheet: Identifiable {
    let project: Project?
    var id: Int64 { project?.id ?? 0 }
}

#Preview {
    if let database = try? AppDatabase() {
        ContentView(model: AppModel(database: database))
    }
}
