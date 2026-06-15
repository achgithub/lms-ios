import SwiftUI
import SwiftData

private enum RoundSheet: String, Identifiable {
    case open, picks, results, declare, summaryPicks, summaryResults, summaryOutcome
    var id: String { rawValue }
}

/// Game detail: header, player roster, and the state-driven round actions
/// (open round → picks → results/close), plus the manager declare-winner override.
struct GameDetailView: View {
    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: RoundSheet?
    /// Set by the results/tie flow when a resolution reinstates players; the
    /// open-round screen is presented for it once the results sheet has closed.
    @State private var pendingAutoOpen: RoundType?
    @State private var autoOpenType: RoundType?

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var currentRound: Round? { game.currentRound }
    private var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }

    /// Most recent round that has any picks recorded — source for a Picks card.
    private var pickableRound: Round? {
        game.rounds.filter { !$0.picks.isEmpty }.max(by: { $0.roundNumber < $1.roundNumber })
    }
    /// Most recent closed round — source for a Results card.
    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }

    var body: some View {
        List {
            infoSection
            roundSection
            summarySection
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet, onDismiss: presentPendingAutoOpen) { which in
            switch which {
            case .open:
                OpenRoundView(game: game)
            case .picks:
                if let round = openRound { PicksEntryView(game: game, round: round) }
            case .results:
                if let round = openRound {
                    ResultsEntryView(game: game, round: round, pendingAutoOpen: $pendingAutoOpen)
                }
            case .declare:
                DeclareWinnersView(game: game) {}
            case .summaryPicks:
                if let round = pickableRound {
                    SummaryShareView(game: game, round: round, type: .picks)
                }
            case .summaryResults:
                if let round = latestClosedRound {
                    SummaryShareView(game: game, round: round, type: .results)
                }
            case .summaryOutcome:
                if let ending = game.lastOutcome, let round = latestClosedRound {
                    SummaryShareView(game: game, round: round, type: .outcome(ending))
                }
            }
        }
        .sheet(item: $autoOpenType) { type in
            OpenRoundView(game: game, roundType: type)
        }
    }

    /// After the results sheet dismisses, open the follow-up round (if a tie
    /// resolution reinstated players). Deferred to here so we never stack two
    /// sheets on the same view.
    private func presentPendingAutoOpen() {
        guard let type = pendingAutoOpen else { return }
        pendingAutoOpen = nil
        autoOpenType = type
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.rawValue.capitalized)
            LabeledContent("Round", value: "\(currentRound?.roundNumber ?? 0)")
        }
    }

    @ViewBuilder
    private var roundSection: some View {
        Section("Round") {
            if game.status == .complete {
                let winners = game.players.filter { $0.status == .winner }
                LabeledContent(winners.count == 1 ? "Winner" : "Winners",
                               value: winners.map(\.name).joined(separator: ", "))
            } else if let round = openRound {
                LabeledContent("Round \(round.roundNumber)", value: round.status.rawValue.capitalized)
                Button { sheet = .picks } label: { Label("Enter Picks", systemImage: "checklist") }
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
            } else {
                Button { sheet = .open } label: { Label("Open Round", systemImage: "calendar.badge.plus") }
                    .disabled(game.activePlayers.isEmpty)
            }

            if game.status != .complete {
                // Available only once a round has been played and at least one
                // player is still standing — nothing to declare before then.
                Button { sheet = .declare } label: {
                    Label("Declare Winner(s)…", systemImage: "trophy")
                }
                .disabled(latestClosedRound == nil || game.activePlayers.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if pickableRound != nil || latestClosedRound != nil {
            Section("Summary Cards") {
                Button { sheet = .summaryPicks } label: {
                    Label("Share Picks Card", systemImage: "square.and.arrow.up")
                }
                .disabled(pickableRound == nil)

                Button { sheet = .summaryResults } label: {
                    Label("Share Results Card", systemImage: "square.and.arrow.up")
                }
                .disabled(latestClosedRound == nil)

                if let ending = game.lastOutcome {
                    Button { sheet = .summaryOutcome } label: {
                        Label("Share \(ending.headline) Card", systemImage: "square.and.arrow.up")
                    }
                    .disabled(latestClosedRound == nil)
                }
            }
        }
    }

    private var playersSection: some View {
        Section("Players (\(game.players.count))") {
            if game.players.isEmpty {
                Text("No players yet.").foregroundStyle(.secondary)
            } else {
                ForEach(sortedPlayers) { player in
                    HStack {
                        Text(player.name)
                        if player.isManager {
                            Text("you")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        if player.status != .active {
                            Text(player.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(player.status == .winner ? .green : .red)
                        }
                    }
                }
            }
            Button { showingAddPlayers = true } label: {
                Label("Add Players", systemImage: "person.badge.plus")
            }
        }
    }
}
