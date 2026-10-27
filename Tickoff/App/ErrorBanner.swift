import SwiftUI

/// Shows a database error above the content; the shell owns the message.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Database error: \(message)")
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .foregroundStyle(.red)
        .padding(10)
        .background(.red.opacity(0.12), in: .rect(cornerRadius: 8))
        .padding([.horizontal, .top], 12)
        .accessibilityElement(children: .combine)
    }
}
