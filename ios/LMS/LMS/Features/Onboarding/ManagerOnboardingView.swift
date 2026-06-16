import SwiftUI

/// The app owner's identity, stored in user defaults. Used to add "you" to games
/// you create and to flag your pick on shared summaries (spec §13b.2).
enum ManagerSettings {
    static let nameKey = "managerName"
}

/// First-launch prompt for the manager's name (shown until a name is set).
struct ManagerOnboardingView: View {
    @Binding var managerName: String
    @State private var draft = ""

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Single localized string key — can't wrap without changing the key.
                    // swiftlint:disable:next line_length
                    Text("What's your name? You'll be added to games you create, and your pick is always shown on shared summary cards — even in anonymous mode — so it's fair on the other players.")
                        .font(.subheadline)
                }
                Section("Your name") {
                    TextField("e.g. Andy", text: $draft)
                        .textInputAutocapitalization(.words)
                        .onSubmit(save)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: save).disabled(trimmed.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        managerName = trimmed
    }
}
