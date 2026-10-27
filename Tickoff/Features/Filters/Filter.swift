/// Which tasks the sidebar selects: everything, or one status.
enum Filter: Hashable, CaseIterable, Sendable {
    case all
    case status(Status)

    static let allCases: [Filter] = [.all] + Status.allCases.map(Filter.status)

    var label: String {
        switch self {
        case .all: "All tasks"
        case .status(let status): status.label
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .status(.todo): "circle"
        case .status(.inProgress): "circle.lefthalf.filled"
        case .status(.done): "checkmark.circle.fill"
        }
    }

    /// The status this filter selects, or `nil` for all tasks.
    var status: Status? {
        switch self {
        case .all: nil
        case .status(let status): status
        }
    }
}
