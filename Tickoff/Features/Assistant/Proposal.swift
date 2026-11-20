import Foundation

/// A change the assistant suggested but nobody has approved yet. `AssistantTools` records these and
/// never writes; applying an approved one is `ChangeBatch`'s job.
struct Proposal: Identifiable, Equatable, Sendable {
    /// Numbered from 1 within an assistant session; the model is told "proposed #n".
    let id: Int
    let change: ProposedChange
    /// One readable line for the proposal card, e.g. "Move “Renew passport” to Work".
    let summary: String
}
