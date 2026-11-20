import SwiftUI

/// The model menu: each available model with its size, whether this Mac can run it and why not, and the
/// download, cancel, delete and use actions. A tight model asks for confirmation before it downloads.
struct ModelPickerView: View {
    let model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.choices, id: \.self) { choice in
                ModelRow(model: model, choice: choice)
                if choice != model.choices.last { Divider() }
            }
            if let notice = model.notice {
                Divider()
                Text(notice).font(.callout).foregroundStyle(.secondary).padding(12)
            }
            if model.choices == [.apple] {
                Divider()
                Text("Downloadable models need macOS 27 or later.")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
            }
        }
        .frame(width: 340)
        .confirmationDialog(
            "Download \(model.confirmingDownload?.model.label ?? "model")?",
            isPresented: Binding(get: { model.confirmingDownload != nil }, set: { if !$0 { model.cancelDownloadConfirmation() } }),
            titleVisibility: .visible
        ) {
            Button("Download Anyway") { model.confirmDownload() }
            Button("Cancel", role: .cancel) { model.cancelDownloadConfirmation() }
        } message: {
            Text(model.confirmingDownload?.reason ?? "")
        }
    }
}

private struct ModelRow: View {
    let model: AssistantModel
    let choice: ModelChoice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: model.choice == choice ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.choice == choice ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label).font(.body)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let note = eligibilityNote {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
    }

    private var availability: ModelAvailability? { model.availability[choice] }
    private var eligibility: Eligibility { model.provider.eligibility(of: choice) }

    private var detail: String {
        guard choice.isDownloadable else { return "Built in. Runs on this Mac." }
        let size = choice.downloadBytes.formatted(.byteCount(style: .file))
        switch availability {
        case .ready: return "\(size), downloaded"
        case .downloading(let fraction): return "Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        default: return "\(size) download"
        }
    }

    private var eligibilityNote: String? {
        if !choice.isDownloadable, case .unavailable(let reason) = availability { return reason }
        switch eligibility {
        case .recommended: return nil
        case .tight(let reason), .blocked(let reason): return reason
        }
    }

    @ViewBuilder private var actions: some View {
        if !choice.isDownloadable {
            useButton
        } else {
            switch availability {
            case .downloading:
                Button("Cancel") { model.cancelDownload() }
            case .ready:
                useButton
                Button("Delete", role: .destructive) { model.delete(choice) }
            default:
                if case .blocked = eligibility {
                    EmptyView()
                } else {
                    Button("Download") { model.download(choice) }
                }
            }
        }
    }

    @ViewBuilder private var useButton: some View {
        if model.choice == choice {
            Text("In use").font(.callout).foregroundStyle(.secondary)
        } else {
            Button("Use") { model.select(choice) }
        }
    }
}
