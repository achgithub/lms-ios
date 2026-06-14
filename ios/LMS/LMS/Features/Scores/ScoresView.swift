import SwiftUI

/// Fixture scores from the Worker (one shared cache for all tiers). The
/// monetization gate is on explicit refresh *actions* in the game flow
/// (see AdGate), not on browsing this list.
struct ScoresView: View {
    @State private var scores: [ScoreDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && scores.isEmpty {
                    ProgressView("Loading scores…")
                } else if let errorMessage, scores.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load scores",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                } else if scores.isEmpty {
                    ContentUnavailableView("No fixtures", systemImage: "sportscourt", description: Text("No fixtures available right now."))
                } else {
                    List(scores) { score in
                        ScoreRow(score: score, teamsById: teamsById)
                    }
                }
            }
            .navigationTitle("Scores")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let scoresReq = APIClient.shared.scores()
            async let teamsReq = APIClient.shared.teams()
            let (scores, teams) = try await (scoresReq, teamsReq)
            self.scores = scores.sorted { $0.id < $1.id }
            self.teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ScoreRow: View {
    let score: ScoreDTO
    let teamsById: [Int: TeamDTO]

    private func name(_ id: Int) -> String { teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)" }
    private func tla(_ id: Int) -> String? { teamsById[id]?.tla }

    private var scoreText: String {
        if let h = score.homeScore, let a = score.awayScore { return "\(h)–\(a)" }
        return "vs"
    }

    private var statusText: String {
        switch score.status {
        case "FINISHED": return "FT"
        case "IN_PLAY", "PAUSED": return score.minute.map { "\($0)'" } ?? "LIVE"
        case "POSTPONED": return "Postponed"
        default: return "—"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            TeamTile(tla: tla(score.homeTeamId), size: .small)
            Text(name(score.homeTeamId)).lineLimit(1)
            Spacer()
            Text(scoreText).bold().monospacedDigit()
            Text(statusText).font(.caption2).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            Spacer()
            Text(name(score.awayTeamId)).lineLimit(1).multilineTextAlignment(.trailing)
            TeamTile(tla: tla(score.awayTeamId), size: .small)
        }
    }
}
