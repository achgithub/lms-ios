import SwiftUI

/// Live fixture scores from a league's Worker, filterable by league, date and
/// team. Switching league targets that league's Worker. The monetization gate is
/// on explicit refresh *actions* in the game flow (see AdGate), not on browsing.
struct ScoresView: View {
    @State private var selectedLeague: LeagueOption = Leagues.home
    @State private var dateFilter: DateFilter = .all
    @State private var selectedTeamId: Int?

    @State private var items: [ScoreItem] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Teams in the loaded league, alphabetical — drives the team filter menu.
    private var teamsSorted: [TeamDTO] {
        teamsById.values.sorted { ($0.shortName ?? $0.name) < ($1.shortName ?? $1.name) }
    }

    /// Items after applying the date + team filters (league is applied at load).
    private var filtered: [ScoreItem] {
        items.filter { item in
            dateFilter.matches(item.kickoff)
                && (selectedTeamId == nil || item.homeTeamId == selectedTeamId || item.awayTeamId == selectedTeamId)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading scores…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load scores",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No fixtures",
                        systemImage: "sportscourt",
                        description: Text(items.isEmpty ? "No fixtures available right now." : "No fixtures match these filters.")
                    )
                } else {
                    List(filtered) { item in
                        ScoreRow(item: item, teamsById: teamsById)
                    }
                }
            }
            .navigationTitle("Scores")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) { refreshButton }
                ToolbarItem(placement: .topBarTrailing) { leagueMenu }
            }
            // Passive cached load when the tab opens or the league changes — not
            // gated (see AdGate). Getting *fresh* data on demand is the gated
            // action: the Refresh button routes through AdGate, and there's no
            // ungated pull-to-refresh, so free users can't bypass the gate.
            .task(id: selectedLeague) { await load() }
        }
    }

    private var refreshButton: some View {
        Button {
            AdGate.run { Task { await load() } }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(isLoading)
    }

    // MARK: Filter controls

    private var leagueMenu: some View {
        Menu {
            Picker("League", selection: $selectedLeague) {
                ForEach(Leagues.all) { league in
                    Text(league.name).tag(league)
                }
            }
        } label: {
            Label(selectedLeague.shortName, systemImage: "trophy")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Date", selection: $dateFilter) {
                Text("All dates").tag(DateFilter.all)
                Text("Today").tag(DateFilter.today)
            }
            Picker("Team", selection: $selectedTeamId) {
                Text("All teams").tag(Int?.none)
                ForEach(teamsSorted) { team in
                    Text(team.shortName ?? team.name).tag(Int?.some(team.externalId))
                }
            }
            if dateFilter != .all || selectedTeamId != nil {
                Divider()
                Button("Clear filters", role: .destructive) {
                    dateFilter = .all
                    selectedTeamId = nil
                }
            }
        } label: {
            Label("Filters", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var filtersActive: Bool { dateFilter != .all || selectedTeamId != nil }

    // MARK: Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        let client = selectedLeague.client
        do {
            // /scores = live (status, minute, score); /fixtures adds kickoff +
            // matchday. Both cover the full season; we join them by match id.
            async let scoresReq = client.scores()
            async let fixturesReq = client.fixtures()
            async let teamsReq = client.teams()
            let (scores, fixtures, teams) = try await (scoresReq, fixturesReq, teamsReq)

            let metaById = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.items = scores
                .map { ScoreItem(score: $0, fixture: metaById[$0.id]) }
                .sorted(by: ScoreItem.byKickoffThenId)
            self.teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a })
            // Drop a team filter that doesn't exist in the newly selected league.
            if let id = selectedTeamId, teamsById[id] == nil { selectedTeamId = nil }
        } catch {
            errorMessage = error.localizedDescription
            self.items = []
        }
        isLoading = false
    }
}

// MARK: - Filter model

/// Date filter for the scores list. `today` uses the device's current calendar.
enum DateFilter: Hashable {
    case all
    case today

    func matches(_ kickoff: Date?) -> Bool {
        switch self {
        case .all: return true
        case .today:
            guard let kickoff else { return false }
            return Calendar.current.isDateInToday(kickoff)
        }
    }
}

// MARK: - Merged view model

/// A live score (from /scores) joined with its fixture metadata (kickoff,
/// matchday from /fixtures). The fixture may be missing if the two feeds drift.
struct ScoreItem: Identifiable {
    let id: Int
    let kickoff: Date?
    let matchday: Int?
    let status: String
    let minute: Int?
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?

    init(score: ScoreDTO, fixture: FixtureDTO?) {
        self.id = score.id
        self.kickoff = fixture.flatMap { ScoreItem.iso.date(from: $0.kickoff) }
        self.matchday = fixture?.matchday
        self.status = score.status
        self.minute = score.minute
        self.homeTeamId = score.homeTeamId
        self.awayTeamId = score.awayTeamId
        self.homeScore = score.homeScore
        self.awayScore = score.awayScore
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Undated fixtures (no kickoff) sort last; otherwise by kickoff then id.
    static func byKickoffThenId(_ a: ScoreItem, _ b: ScoreItem) -> Bool {
        switch (a.kickoff, b.kickoff) {
        case let (x?, y?): return x == y ? a.id < b.id : x < y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return a.id < b.id
        }
    }
}

// MARK: - Row

private struct ScoreRow: View {
    let item: ScoreItem
    let teamsById: [Int: TeamDTO]

    private func name(_ id: Int) -> String { teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)" }
    private func tla(_ id: Int) -> String? { teamsById[id]?.tla }

    private var scoreText: String {
        if let h = item.homeScore, let a = item.awayScore { return "\(h)–\(a)" }
        return "vs"
    }

    private var statusText: String {
        switch item.status {
        case "FINISHED": return "FT"
        case "IN_PLAY", "PAUSED": return item.minute.map { "\($0)'" } ?? "LIVE"
        case "POSTPONED": return "Postponed"
        default:
            if let kickoff = item.kickoff {
                return kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            }
            return "—"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            TeamTile(tla: tla(item.homeTeamId), size: .small)
            Text(name(item.homeTeamId)).lineLimit(1)
            Spacer()
            Text(scoreText).bold().monospacedDigit()
            Text(statusText).font(.caption2).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            Spacer()
            Text(name(item.awayTeamId)).lineLimit(1).multilineTextAlignment(.trailing)
            TeamTile(tla: tla(item.awayTeamId), size: .small)
        }
    }
}
