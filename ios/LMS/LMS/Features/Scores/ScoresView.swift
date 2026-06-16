import SwiftUI

/// Live fixture scores across the manager's enabled leagues. A magnifier opens a
/// search panel (league pills, team text + Home/Away, matchday, date range, A–Z
/// sort) so a manager can look things up fast without leaving the app. The
/// monetization gate is on explicit refresh *actions* (see AdGate), not browsing.
struct ScoresView: View {
    @Environment(EnabledLeagues.self) private var enabled

    @State private var items: [ScoreItem] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshed: Date?

    // Search / filter
    @State private var selectedLeagueIds: Set<String> = []
    @State private var teamQuery = ""
    @State private var homeAway: HomeAwayFilter = .all
    @State private var matchdayFilter: Int?
    @State private var dateRangeOn = false
    @State private var dateFrom = Date().addingTimeInterval(-1 * 24 * 3600)
    @State private var dateTo = Date().addingTimeInterval(14 * 24 * 3600)
    @State private var sortAZ = false
    @State private var showSearch = false

    /// Leagues currently included (defaults to every enabled league).
    private var activeLeagueIds: Set<String> {
        selectedLeagueIds.isEmpty ? Set(enabled.leagues.map(\.id)) : selectedLeagueIds
    }

    private var matchdays: [Int] { Array(Set(items.compactMap(\.matchday))).sorted() }

    private func name(_ id: Int) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }

    private func teamMatches(_ item: ScoreItem) -> Bool {
        let q = teamQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let home = name(item.homeTeamId).localizedCaseInsensitiveContains(q)
        let away = name(item.awayTeamId).localizedCaseInsensitiveContains(q)
        switch homeAway {
        case .all:  return home || away
        case .home: return home
        case .away: return away
        }
    }

    private func dateInRange(_ kickoff: Date?) -> Bool {
        guard let kickoff else { return false }
        let cal = Calendar.current
        let lo = cal.startOfDay(for: dateFrom)
        let hi = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dateTo)) ?? dateTo
        return kickoff >= lo && kickoff < hi
    }

    private var filtered: [ScoreItem] {
        let result = items.filter { item in
            activeLeagueIds.contains(item.leagueId)
                && (matchdayFilter == nil || item.matchday == matchdayFilter)
                && (!dateRangeOn || dateInRange(item.kickoff))
                && teamMatches(item)
        }
        if sortAZ {
            return result.sorted { name($0.homeTeamId).localizedCaseInsensitiveCompare(name($1.homeTeamId)) == .orderedAscending }
        }
        return result.sorted(by: ScoreItem.byKickoffThenId)
    }

    private var filtersActive: Bool {
        !teamQuery.isEmpty || matchdayFilter != nil || dateRangeOn || sortAZ
            || (selectedLeagueIds.count != enabled.leagues.count && !selectedLeagueIds.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading scores…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Couldn't load scores", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No fixtures",
                        systemImage: "sportscourt",
                        description: Text(items.isEmpty ? "No fixtures available right now." : "No fixtures match your search.")
                    )
                } else {
                    List(filtered) { item in
                        ScoreRow(item: item, teamsById: teamsById)
                    }
                }
            }
            .navigationTitle("Scores")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: {
                        Image(systemName: filtersActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AdGate.run { Task { await load(force: true) } } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showSearch) {
                ScoresSearchSheet(
                    leagues: enabled.leagues,
                    matchdays: matchdays,
                    selectedLeagueIds: $selectedLeagueIds,
                    teamQuery: $teamQuery,
                    homeAway: $homeAway,
                    matchdayFilter: $matchdayFilter,
                    dateRangeOn: $dateRangeOn,
                    dateFrom: $dateFrom,
                    dateTo: $dateTo,
                    sortAZ: $sortAZ
                )
            }
            // Load every enabled league once; pills filter client-side so toggling
            // them is instant and never re-hits the network.
            .task(id: enabled.leagues.map(\.id)) {
                if selectedLeagueIds.isEmpty { selectedLeagueIds = Set(enabled.leagues.map(\.id)) }
                await load(force: false)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    // Shared footer with Standings: last-refreshed time + the non-affiliation
    // disclaimer, same look and feel.
    private var footer: some View {
        VStack(spacing: 4) {
            if let lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Single localized string key — can't wrap without changing the key.
            // swiftlint:disable:next line_length
            Text("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
        .background(.bar)
    }

    /// Loads scores for every enabled league. `force` (the ad-gated refresh)
    /// always hits the network and overwrites the per-league cache; otherwise each
    /// league is served from its cache, fetching only the first time (empty cache).
    /// This is what stops a relaunch from being a free refresh.
    private func load(force: Bool) async {
        isLoading = true
        errorMessage = nil
        var allItems: [ScoreItem] = []
        var allTeams: [Int: TeamDTO] = [:]
        var dates: [Date] = []
        do {
            for league in enabled.leagues {
                let key = LeagueDataCache.scoresKey(league.id)
                if !force, let cached = LeagueDataCache.load(LeagueDataCache.Scores.self, key: key) {
                    allItems += cached.items
                    for team in cached.teams { allTeams[team.externalId] = team }
                    dates.append(cached.date)
                } else {
                    let client = league.client
                    async let scoresReq = client.scores()
                    async let fixturesReq = client.fixtures()
                    async let teamsReq = client.teams()
                    let (scores, fixtures, teams) = try await (scoresReq, fixturesReq, teamsReq)
                    let metaById = Dictionary(fixtures.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    let leagueItems = scores.map { ScoreItem(score: $0, fixture: metaById[$0.id], leagueId: league.id) }
                    allItems += leagueItems
                    for team in teams { allTeams[team.externalId] = team }
                    let now = Date()
                    dates.append(now)
                    LeagueDataCache.save(LeagueDataCache.Scores(date: now, items: leagueItems, teams: teams), key: key)
                }
            }
            items = allItems
            teamsById = allTeams
            lastRefreshed = dates.max()
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
        isLoading = false
    }
}

// MARK: - Search panel

enum HomeAwayFilter: Hashable { case all, home, away }

private struct ScoresSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let leagues: [LeagueOption]
    let matchdays: [Int]
    @Binding var selectedLeagueIds: Set<String>
    @Binding var teamQuery: String
    @Binding var homeAway: HomeAwayFilter
    @Binding var matchdayFilter: Int?
    @Binding var dateRangeOn: Bool
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var sortAZ: Bool

    var body: some View {
        NavigationStack {
            Form {
                if leagues.count > 1 {
                    Section("Leagues") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(leagues) { league in leaguePill(league) }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Team") {
                    TextField("Search team", text: $teamQuery)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Picker("Show", selection: $homeAway) {
                        Text("All").tag(HomeAwayFilter.all)
                        Text("Home").tag(HomeAwayFilter.home)
                        Text("Away").tag(HomeAwayFilter.away)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sort") {
                    Picker("Sort", selection: $sortAZ) {
                        Text("Kick-off").tag(false)
                        Text("A–Z").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if !matchdays.isEmpty {
                    Section("Matchday") {
                        Picker("Matchday", selection: $matchdayFilter) {
                            Text("All").tag(Int?.none)
                            ForEach(matchdays, id: \.self) { Text("MD \($0)").tag(Int?.some($0)) }
                        }
                    }
                }

                Section("Date range") {
                    Toggle("Filter by date", isOn: $dateRangeOn.animation())
                    if dateRangeOn {
                        DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                    }
                }

                Section {
                    Button("Clear all", role: .destructive) { clearAll() }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func leaguePill(_ league: LeagueOption) -> some View {
        let on = selectedLeagueIds.isEmpty || selectedLeagueIds.contains(league.id)
        return Button {
            toggle(league.id)
        } label: {
            Text(league.shortName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if selectedLeagueIds.contains(id) {
            if selectedLeagueIds.count > 1 { selectedLeagueIds.remove(id) }  // keep at least one
        } else {
            selectedLeagueIds.insert(id)
        }
    }

    private func clearAll() {
        selectedLeagueIds = Set(leagues.map(\.id))
        teamQuery = ""
        homeAway = .all
        matchdayFilter = nil
        dateRangeOn = false
        sortAZ = false
    }
}

// MARK: - Merged view model

/// A live score (from /scores) joined with its fixture metadata (kickoff,
/// matchday from /fixtures), tagged with its league so multi-league views can
/// filter by league. The fixture may be missing if the two feeds drift.
struct ScoreItem: Identifiable, Codable {
    let id: Int
    let leagueId: String
    let kickoff: Date?
    let matchday: Int?
    let status: String
    let minute: Int?
    let homeTeamId: Int
    let awayTeamId: Int
    let homeScore: Int?
    let awayScore: Int?

    init(score: ScoreDTO, fixture: FixtureDTO?, leagueId: String) {
        self.id = score.id
        self.leagueId = leagueId
        // Use the same lenient parser as fixtures — the feed's kickoff has no
        // fractional seconds, so a stricter formatter would silently drop it.
        self.kickoff = fixture.flatMap { FixtureFormat.kickoffDate($0.kickoff) }
        self.matchday = fixture?.matchday
        self.status = score.status
        self.minute = score.minute
        self.homeTeamId = score.homeTeamId
        self.awayTeamId = score.awayTeamId
        self.homeScore = score.homeScore
        self.awayScore = score.awayScore
    }

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

/// Score row — same compact look as a fixture row (home tile/TLA · score · away
/// TLA/tile) with the kick-off date/time + matchday on the trailing edge. A small
/// live indicator (FT / 45' / Postp.) sits under the score.
private struct ScoreRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: ScoreItem
    let teamsById: [Int: TeamDTO]
    @State private var expanded = false

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }
    private var scoreFont: Font { isPad ? .title3 : .subheadline }
    private var centreWidth: CGFloat { isPad ? 56 : 44 }

    private func shortName(_ id: Int) -> String { teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)" }
    private func fullName(_ id: Int) -> String { teamsById[id]?.name ?? "Team \(id)" }
    private func displayName(_ id: Int) -> String { expanded ? fullName(id) : shortName(id) }

    private var scoreText: String {
        if let h = item.homeScore, let a = item.awayScore { return "\(h)–\(a)" }
        return "v"
    }

    /// Live/finished indicator shown under the score; nil for upcoming fixtures
    /// (their date/time already shows on the right).
    private var liveStatus: (text: String, color: Color)? {
        switch item.status {
        case "FINISHED":          return ("FT", .secondary)
        case "IN_PLAY", "PAUSED": return (item.minute.map { "\($0)'" } ?? "LIVE", .green)
        case "POSTPONED":         return ("Postp.", .orange)
        default:                  return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Home — name (truncates; tap the row to expand to full name).
            Text(displayName(item.homeTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Centre — score (+ live indicator), fixed width so it stays put.
            VStack(spacing: 1) {
                Text(scoreText).font(scoreFont).bold().monospacedDigit()
                if let live = liveStatus {
                    Text(live.text).font(.caption2).foregroundStyle(live.color).lineLimit(1)
                }
            }
            .frame(width: centreWidth)

            // Away — name, mirror of home.
            Text(displayName(item.awayTeamId)).font(nameFont).lineLimit(expanded ? nil : 1)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Trailing — date / time / matchday, fixed width on the right edge.
            VStack(alignment: .trailing, spacing: 1) {
                if let kickoff = item.kickoff {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(kickoff, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                }
                if let md = item.matchday {
                    Text("MD \(md)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: isPad ? 96 : 74, alignment: .trailing)
        }
        .padding(.vertical, isPad ? 4 : 0)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
    }
}
