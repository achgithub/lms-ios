import Combine
import SwiftData
import SwiftUI

/// Enter per-fixture results (or pull them from the server) and close the round
/// (§6.5). Closing computes eliminations; if everyone goes out together the tie
/// resolution sheet appears; a single survivor wins automatically.
struct ResultsEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    let round: Round
    /// Set true when closing leaves everyone eliminated; the parent then presents
    /// the tie resolution (at the top level, after this sheet dismisses).
    @Binding var pendingResolve: Bool

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var outcomes: [Int: FixtureOutcome] = [:]
    @State private var lastPulled: Date?

    // Refresh throttle — shared with Scores via the same 120s live-pull clock
    // (see `LeagueDataCache.sharedLiveThrottleUntil`): this action is pulling
    // live results, the same job as Scores, just via /fixtures instead of
    // /scores. Without sharing the clock, a manager could pull here, then
    // immediately pull again on the Scores tab (two independent cooldowns).
    @State private var now = Date()
    @State private var freshUntil: Date?
    private var isThrottled: Bool { freshUntil.map { now < $0 } ?? false }

    private func fixturesThrottleUntil() -> Date? {
        LeagueDataCache.sharedLiveThrottleUntil(for: game.leagues.map(\.id))
    }

    private var roundFixtures: [FixtureDTO] {
        guard let data else { return [] }
        let ids = Set(round.fixtureIds)
        return data.fixtures.filter { ids.contains($0.id) }.sorted { $0.kickoff < $1.kickoff }
    }

    /// Every fixture in the round has a result entered — required before closing.
    private var allResultsSet: Bool {
        !roundFixtures.isEmpty && roundFixtures.allSatisfy { outcomes[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    list
                }
            }
            .navigationTitle("Results · Round \(round.roundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    // Free users watch a rewarded ad to pull fresh results;
                    // subscribers pull instantly (see AdGate). Greyed while
                    // throttled, matching Scores.
                    Button {
                        AdGate.run { Task { await pullFromServer() } }
                    } label: {
                        Label("Pull results from server", systemImage: "arrow.down.circle")
                    }
                    .disabled(isLoading || isThrottled)
                }
            }
            // Only advance the clock while throttled, so we don't re-render every
            // second once the button is live again (see Scores).
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
                if isThrottled { now = tick }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let lastPulled {
                        Text("Updated \(lastPulled.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if isThrottled, let freshUntil {
                        let remaining = Duration.seconds(max(0, freshUntil.timeIntervalSince(now)))
                        Text("Refresh available in \(remaining.formatted(.time(pattern: .minuteSecond)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Independence / non-affiliation disclaimer, matching Scores.
                    // swiftlint:disable:next line_length
                    Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button { close() } label: {
                        Text("Close Round").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    .disabled(round.status == .closed || !allResultsSet)
                }
                .padding(.bottom, 6)
                .padding(.horizontal)
                .background(.bar)
            }
            .task { await load() }
        }
    }

    private var list: some View {
        List {
            ForEach(roundFixtures) { fixture in
                VStack(alignment: .leading, spacing: 6) {
                    FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                    Picker("Result", selection: outcomeBinding(for: fixture.id)) {
                        Text("—").tag(FixtureOutcome?.none)
                        ForEach(FixtureOutcome.allCases) { Text($0.label).tag(FixtureOutcome?.some($0)) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func outcomeBinding(for id: Int) -> Binding<FixtureOutcome?> {
        Binding(get: { outcomes[id] }, set: { outcomes[id] = $0 })
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            data = try await LeagueData.load(for: game.leagues)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Re-arm the throttle from the now-current caches (greyed if all fresh).
        now = Date()
        freshUntil = fixturesThrottleUntil()
        isLoading = false
    }

    private func pullFromServer() async {
        // Same shared pull as Scores' refresh (LeagueData.pullLiveScores) — one
        // fetch, one cooldown, no separate ad for the same underlying data. It
        // writes the Scores cache and patches the Fixtures cache for any
        // FINISHED match; reloading from cache below picks that up without a
        // second network call. Falls back to current data on failure.
        for league in game.leagues { _ = try? await LeagueData.pullLiveScores(for: league) }
        if let fresh = try? await LeagueData.load(for: game.leagues) {
            data = fresh
            lastPulled = Date()
        }
        for fixture in roundFixtures {
            if fixture.status == "POSTPONED" {
                outcomes[fixture.id] = .postponed
            } else if let outcome = GameLogicService.outcome(fromWinner: fixture.winner) {
                outcomes[fixture.id] = outcome
            }
        }
        // Re-arm the throttle from the now-current caches (greyed if all fresh).
        now = Date()
        freshUntil = fixturesThrottleUntil()
    }

    private func close() {
        guard data != nil else { return }
        // Apply each entered fixture result to the picks on both teams.
        for fixture in roundFixtures {
            if let outcome = outcomes[fixture.id] {
                GameLogicService.applyResult(
                    homeTeamId: fixture.homeTeamId,
                    awayTeamId: fixture.awayTeamId,
                    outcome: outcome,
                    round: round
                )
            }
        }

        let result = GameLogicService.closeRound(round, game: game, context: context)

        if result.allEliminated {
            // Hand off to the parent to present the resolution at the top level
            // (avoids stacking a sheet on this one).
            pendingResolve = true
            dismiss()
        } else if result.remainingActive == 1,
                  let winner = game.players.first(where: { $0.status == .active }) {
            GameLogicService.apply(.winners([winner.id]), game: game)
            dismiss()
        } else {
            dismiss()
        }
    }
}
