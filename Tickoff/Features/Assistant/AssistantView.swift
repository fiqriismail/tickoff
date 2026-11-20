import SwiftUI

/// The assistant panel shown in the window's inspector: model header, transcript, pending proposals and the
/// input. It reads and drives an `AssistantModel`; nothing here touches the database.
struct AssistantView: View {
    let model: AssistantModel
    @State private var draft = ""
    @State private var showsModels = false
    @FocusState private var inputFocused: Bool

    private static var margin: CGFloat { 16 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if !model.proposals.isEmpty {
                Divider()
                ProposalList(model: model)
            }
            Divider()
            if let message = problem {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.margin)
                    .padding(.top, 8)
            }
            input
        }
        .task { await model.refreshAvailability() }
        .onChange(of: model.choice) { _Concurrency.Task { await model.refreshAvailability() } }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { showsModels.toggle() } label: {
                Label(model.choice.label, systemImage: "cpu")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showsModels, arrowEdge: .bottom) { ModelPickerView(model: model) }
            .help("Choose the assistant’s model")
            Spacer()
            Button { model.newConversation() } label: { Label("New Conversation", systemImage: "square.and.pencil") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.messages.isEmpty && model.proposals.isEmpty)
                .help("Start a new conversation")
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 8)
    }

    /// Why the model can't answer right now, from a failed turn or the chosen model's availability.
    private var problem: String? {
        if case .failed(let message) = model.status { return message }
        switch model.availability[model.choice] {
        case .unavailable(let reason): return reason
        case .notDownloaded: return "Download this model from the model menu to use it."
        case .downloading: return "This model is still downloading."
        default: return nil
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    ContentUnavailableView(
                        "Ask Tickoff", systemImage: "sparkles",
                        description: Text("Ask me to add, change, move or complete tasks, or to log daily-goal progress. I’ll propose changes for you to review first."))
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { MessageRow(message: $0, isStreaming: model.isBusy && $0.id == model.messages.last?.id) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(Self.margin)
                }
            }
            .onChange(of: model.messages.last?.text) { proxy.scrollTo("end") }
            .onChange(of: model.messages.count) { proxy.scrollTo("end") }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Input

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Tickoff…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)
            if model.isBusy {
                Button(action: model.stop) { Label("Stop", systemImage: "stop.circle.fill") }
                    .help("Stop the answer")
            } else {
                Button(action: send) { Label("Send", systemImage: "arrow.up.circle.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title2)
        .padding(Self.margin)
    }

    private func send() {
        model.send(draft)
        draft = ""
    }
}

/// One chat bubble; the user's is tinted and right-aligned, the assistant's is plain text.
private struct MessageRow: View {
    let message: AssistantModel.Message
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            Group {
                if message.text.isEmpty && isStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message.text).font(.body).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The pending proposals: Apply all, Discard all, and a card per proposal with Apply and Discard.
private struct ProposalList: View {
    let model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proposed changes").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Discard All", role: .destructive, action: model.discardAll)
                Button("Apply All", action: model.applyAll).buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.proposals) { proposal in
                        HStack {
                            Text(proposal.summary).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Discard") { model.discard(proposal) }
                            Button("Apply") { model.apply(proposal) }
                        }
                        .controlSize(.small)
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(16)
    }
}
