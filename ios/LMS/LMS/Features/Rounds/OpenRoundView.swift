import SwiftUI
import SwiftData

/// Open a new round: choose a league, narrow fixtures (matchday / date range /
/// unplayed-only) and select the ones the round runs on, then set the picks
/// deadline (spec §6.3). Defaults to upcoming (unplayed) fixtures so managers
/// see selectable games first.
struct OpenRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let game: Game
    /// The kind of round to open. Tie follow-ups pass `.playoff`/`.rollover`.
    var roundType: RoundType = .normal
    /// Called after a round is successfully opened (e.g. to dismiss a parent).
    var onOpened: () -> Void = {}

    @State private var data: LeagueData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Filters — date is the primary driver (matchday numbers don't line up across
    // leagues), so the date window is on by default.
    @State private var leagueFilter: String?         // nil = all the game's leagues
    @State private var unplayedOnly = true           // default: upcoming fixtures
    @State private var dateFilterOn = true
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)

    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()

    /// The league(s) this game runs in — fixtures are pooled across them.
    private var gameLeagues: [LeagueOption] { game.leagues }
    private var isBlended: Bool { gameLeagues.count > 1 }

    private var allFixtures: [FixtureDTO] { data?.fixtures ?? [] }

    /// We only ever show the schedule four weeks ahead — a hard forward horizon.
    /// Applied regardless of the date filter (and the date picker can't reach past
    /// it), so a round is always opened on fixtures inside the window.
    private static let horizon: TimeInterval = 28 * 24 * 3600
    private var horizonEnd: Date { Date().addingTimeInterval(Self.horizon) }
    private func withinHorizon(_ f: FixtureDTO) -> Bool {
        guard let k = FixtureFormat.kickoffDate(f.kickoff) else { return true }
        return k <= horizonEnd
    }

    /// The league a fixture belongs to (via its home team's league).
    private func leagueId(of f: FixtureDTO) -> String? { data?.leagueIdByTeam[f.homeTeamId] }

    /// Fixtures after every active filter, sorted by kickoff.
    private var visibleFixtures: [FixtureDTO] {
        allFixtures.filter { f in
            withinHorizon(f)
                && (leagueFilter == nil || leagueId(of: f) == leagueFilter)
                && (!unplayedOnly || Self.isUnplayed(f))
                && (!dateFilterOn || dateInRange(f))
        }
        .sorted { $0.kickoff < $1.kickoff }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && data == nil {
                    ProgressView("Loading fixtures…")
                } else if let errorMessage, data == nil {
                    ContentUnavailableView("Couldn't load fixtures", systemImage: "wifi.slash", description: Text(errorMessage))
                } else {
                    form
                }
            }
            .navigationTitle("Open \(roundType.openTitle) \(GameLogicService.nextRoundNumber(for: game))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { create() }.disabled(selectedFixtureIds.isEmpty || !enoughPlayers)
                }
            }
            .task { await load() }
        }
    }

    /// A round needs at least two active players — otherwise there's no contest
    /// and a single player could be "eliminated" into a nonsensical one-way tie.
    private var enoughPlayers: Bool { game.activePlayers.count >= 2 }

    private var form: some View {
        Form {
            if !enoughPlayers {
                Section {
                    Label("A game needs at least 2 players to start a round.",
                          systemImage: "person.2.slash")
                        .foregroundStyle(.orange)
                }
            }

            Section("Filters") {
                // Only show the league control when there's an actual choice — a
                // single-league game uses that league silently (matches New Game).
                if isBlended {
                    Picker("League", selection: $leagueFilter) {
                        Text("All leagues").tag(String?.none)
                        ForEach(gameLeagues) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
                Toggle("Unplayed only", isOn: $unplayedOnly)
                Toggle("Filter by date", isOn: $dateFilterOn.animation())
                if dateFilterOn {
                    DatePicker("From", selection: $dateFrom, in: ...horizonEnd, displayedComponents: .date)
                    DatePicker("To", selection: $dateTo, in: dateFrom...horizonEnd, displayedComponents: .date)
                }
            }

            Section {
                if visibleFixtures.isEmpty {
                    Text("No fixtures match these filters.").foregroundStyle(.secondary)
                } else {
                    ForEach(visibleFixtures) { fixture in
                        Button {
                            toggle(fixture.id)
                        } label: {
                            HStack {
                                Image(systemName: selectedFixtureIds.contains(fixture.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedFixtureIds.contains(fixture.id) ? .green : .secondary)
                                FixtureLabel(fixture: fixture, teamsById: data?.teamsById ?? [:])
                                if isBlended, let lid = leagueId(of: fixture), let l = Leagues.byId(lid) {
                                    Text(l.shortName)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Fixtures (\(selectedFixtureIds.count) selected)")
                    Spacer()
                    if !visibleFixtures.isEmpty {
                        Button(allVisibleSelected ? "Deselect all" : "Select all") {
                            toggleSelectAllVisible()
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }

            Section {
                DatePicker("Picks due by", selection: $deadline)
            } header: {
                Text("Deadline")
            } footer: {
                Text("Defaults to 24 hours before the first selected kick-off. A guide for the manager — picks aren't locked automatically.")
            }
        }
    }

    // MARK: Selection

    private var allVisibleSelected: Bool {
        !visibleFixtures.isEmpty && visibleFixtures.allSatisfy { selectedFixtureIds.contains($0.id) }
    }

    private func toggle(_ id: Int) {
        if selectedFixtureIds.contains(id) { selectedFixtureIds.remove(id) } else { selectedFixtureIds.insert(id) }
        syncDeadlineToSelection()
    }

    private func toggleSelectAllVisible() {
        if allVisibleSelected {
            visibleFixtures.forEach { selectedFixtureIds.remove($0.id) }
        } else {
            visibleFixtures.forEach { selectedFixtureIds.insert($0.id) }
        }
        syncDeadlineToSelection()
    }

    /// Default the deadline to 24 hours before the earliest selected kick-off
    /// (info only — the manager can change it; nothing is enforced).
    private func syncDeadlineToSelection() {
        let kickoffs = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
        if let earliest = kickoffs.min() {
            deadline = earliest.addingTimeInterval(-24 * 3600)
        }
    }

    // MARK: Filtering helpers

    private static func isUnplayed(_ f: FixtureDTO) -> Bool {
        f.status != "FINISHED" && f.status != "CANCELLED"
    }

    private func dateInRange(_ f: FixtureDTO) -> Bool {
        guard let k = FixtureFormat.kickoffDate(f.kickoff) else { return false }
        let cal = Calendar.current
        return k >= cal.startOfDay(for: dateFrom) && k < cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: dateTo) ?? dateTo)
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fresh = try await LeagueData.load(for: gameLeagues)
            data = fresh
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() {
        GameLogicService.openRound(
            in: game,
            fixtureIds: Array(selectedFixtureIds),
            deadline: deadline,
            roundType: roundType,
            context: context
        )
        onOpened()
        dismiss()
    }
}
