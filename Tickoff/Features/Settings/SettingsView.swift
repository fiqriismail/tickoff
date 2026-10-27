import SwiftUI

/// The Settings window (⌘,): appearance preferences, applied live and saved on every change.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: binding(\.mode)) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Accent colour") {
                    AccentPicker(selection: binding(\.accent))
                }

                Picker("Text size", selection: binding(\.scale)) {
                    ForEach(UiScale.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance").bold()
            }

            Section {
                Toggle(isOn: binding(\.compactCards)) {
                    Text("Compact cards")
                    Text("Tighter spacing so more tasks fit on screen")
                }
                Toggle(isOn: binding(\.showNotes)) {
                    Text("Show notes on cards")
                    Text("Preview the first line of a task's notes")
                }
            } header: {
                Text("Task list").bold()
            }

            Section {
                Button("Reset to defaults") { model.resetToDefaults() }
            }

            if let message = model.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Appearance, Value>) -> Binding<Value> {
        Binding(
            get: { model.appearance[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } })
    }
}

/// A row of colour dots; the selected one is ringed.
private struct AccentPicker: View {
    @Binding var selection: Accent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Accent.allCases, id: \.self) { accent in
                Button {
                    selection = accent
                } label: {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if accent == .system {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .overlay {
                            if selection == accent {
                                Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
                            }
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(accent.label)
                .accessibilityLabel(accent.label)
                .accessibilityAddTraits(selection == accent ? .isSelected : [])
            }
        }
    }
}

#Preview {
    if let database = try? AppDatabase() {
        SettingsView(model: SettingsModel(store: SettingsStore(database: database)))
    }
}
