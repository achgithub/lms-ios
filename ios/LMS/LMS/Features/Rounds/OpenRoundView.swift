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

    // Filters
    @State private var leagueFilter: String?         // nil = all the game's leagues
    @State private var matchdayFilter: Int?          // nil = all matchdays
    @State private var unplayedOnly = true           // default: upcoming fixtures
    @State private var dateFilterOn = false
    @State private var dateFrom = Date()
    @State private var dateTo = Date().addingTimeInterval(7 * 24 * 3600)

    @State private var selectedFixtureIds: Set<Int> = []
    @State private var deadline = Date()

    /// The league(s) this game runs in — fixtures are pooled across them.
    private var gameLeagues: [LeagueOption] { game.leagues }
    private var isBlended: Bool { gameLeagues.count > 1 }

    private var allFixtures: [FixtureDTO] { data?.fixtures ?? [] }

    private var matchdays: [Int] {
        Array(Set(allFixtures.compactMap(\.matchday))).sorted()
    }

    /// The league a fixture belongs to (via its home team's league).
    private func leagueId(of f: FixtureDTO) -> String? { data?.leagueIdByTeam[f.homeTeamId] }

    /// Fixtures after every active filter, sorted by kickoff.
    private var visibleFixtures: [FixtureDTO] {
        allFixtures.filter { f in
            (leagueFilter == nil || leagueId(of: f) == leagueFilter)
                && (matchdayFilter == nil || f.matchday == matchdayFilter)
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
                    Button("Open") { create() }.disabled(selectedFixtureIds.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section("Filters") {
                if isBlended {
                    Picker("League", selection: $leagueFilter) {
                        Text("All leagues").tag(String?.none)
                        ForEach(gameLeagues) { Text($0.name).tag(String?.some($0.id)) }
                    }
                } else {
                    LabeledContent("League", value: gameLeagues.first?.name ?? "—")
                }
                Picker("Matchday", selection: $matchdayFilter) {
                    Text("All").tag(Int?.none)
                    ForEach(matchdays, id: \.self) { Text("Matchday \($0)").tag(Int?.some($0)) }
                }
                Toggle("Unplayed only", isOn: $unplayedOnly)
                Toggle("Filter by date", isOn: $dateFilterOn.animation())
                if dateFilterOn {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                    DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
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

            Section("Deadline") {
                DatePicker("Picks due by", selection: $deadline)
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

    /// Default the deadline to the earliest selected kickoff.
    private func syncDeadlineToSelection() {
        let kickoffs = allFixtures
            .filter { selectedFixtureIds.contains($0.id) }
            .compactMap { FixtureFormat.kickoffDate($0.kickoff) }
        if let earliest = kickoffs.min() { deadline = earliest }
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
            // Single-league: default to the first matchday that still has unplayed
            // fixtures (the current/next one) and preselect it. Blended games mix
            // leagues' matchday numbers, so leave the pool open for the manager.
            if !isBlended {
                let firstUnplayedMatchday = fresh.fixtures
                    .filter { Self.isUnplayed($0) }
                    .compactMap(\.matchday)
                    .min()
                matchdayFilter = firstUnplayedMatchday ?? matchdays.first
                selectedFixtureIds = Set(visibleFixtures.map(\.id))
                syncDeadlineToSelection()
            }
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
