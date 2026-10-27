import SwiftUI

/// Placeholder shell: an empty sidebar so the traffic lights sit over it, as in the Rust app.
/// #15 replaces this with the real sidebar, filters and task list.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {}
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Text("Tickoff")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    ContentView()
}
