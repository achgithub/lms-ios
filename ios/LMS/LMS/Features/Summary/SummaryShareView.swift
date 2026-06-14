import SwiftUI

/// Loads the team data, builds the `SummaryData`, renders the §13b card to a
/// `UIImage`, previews it, and offers the system share sheet (spec §13b.5).
struct SummaryShareView: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let round: Round
    let type: SummaryType

    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var rendered: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var title: String {
        type == .picks ? "Picks · Round \(round.roundNumber)" : "Results · Round \(round.roundNumber)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let rendered {
                    ScrollView {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8)
                            .padding()
                    }
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't build card", systemImage: "photo.badge.exclamationmark",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("Rendering card…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let rendered {
                    ToolbarItem(placement: .primaryAction) {
                        // Free users watch a rewarded ad before the share sheet;
                        // subscribers share instantly (see AdGate). Presented
                        // programmatically so the ad can run first.
                        Button {
                            AdGate.run {
                                ImageSharePresenter.present(image: rendered, title: title)
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await build() }
        }
    }

    private func build() async {
        isLoading = true
        errorMessage = nil
        // Team data drives tiles/names; degrade gracefully to ids if offline.
        do {
            let teams = try await APIClient.shared.teams()
            teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // Non-fatal — render with "Team <id>" fallbacks rather than failing.
            teamsById = [:]
        }
        let managerId = game.players.first(where: { $0.isManager })?.id
        let data = SummaryData.make(type: type, game: game, round: round, teamsById: teamsById, managerPlayerId: managerId)
        let renderer = ImageRenderer(content: SummaryCardView(data: data))
        renderer.scale = 3.0   // @3x — crisp in WhatsApp (spec §13b.4)
        if let image = renderer.uiImage {
            rendered = image
        } else {
            errorMessage = "The card image could not be generated."
        }
        isLoading = false
    }
}
