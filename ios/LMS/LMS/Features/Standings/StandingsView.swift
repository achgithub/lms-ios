import SwiftUI

/// League table from the Worker, with §15 team tiles. Browsing is a free live
/// read; the explicit refresh button is the free-tier rewarded-ad gate (matches
/// Scores), and shows when the data was last refreshed.
struct StandingsView: View {
    @Environment(EnabledLeagues.self) private var enabled
    @State private var selectedLeague: LeagueOption?
    @State private var standings: [StandingDTO] = []
    @State private var teamsById: [Int: TeamDTO] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshed: Date?

    private var league: LeagueOption { selectedLeague ?? enabled.leagues.first ?? Leagues.home }
    private var leagueBinding: Binding<LeagueOption> {
        Binding(get: { league }, set: { selectedLeague = $0 })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && standings.isEmpty {
                    ProgressView("Loading standings…")
                } else if let errorMessage, standings.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load standings",
                        systemImage: "wifi.slash",
                        description: Text(errorMessage)
                    )
                } else {
                    List(standings) { row in
                        StandingRow(row: row, team: teamsById[row.teamId])
                    }
                }
            }
            .navigationTitle("Standings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Same gate as Scores: a fresh pull is a server fetch, so free
                    // users watch a rewarded ad first (see AdGate); subscribers
                    // refresh instantly.
                    Button { AdGate.run { Task { await load(force: true) } } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                if enabled.leagues.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("League", selection: leagueBinding) {
                                ForEach(enabled.leagues) { Text($0.name).tag($0) }
                            }
                        } label: {
                            Label(league.shortName, systemImage: "trophy")
                        }
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        Text(league.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            // Reloads when the chosen league changes (browsing, so not ad-gated —
            // the explicit refresh button is the gated fetch action).
            .task(id: league) { await load(force: false) }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let lastRefreshed {
                        Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Independence / non-affiliation disclaimer (names + data are
                    // factual, descriptive use only). Single localized key — can't wrap.
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
        }
    }

    /// `force` (the ad-gated refresh) hits the network and overwrites the cache;
    /// otherwise the league is served from its cache, fetching only the first time
    /// (empty cache) — so a relaunch isn't a free refresh.
    private func load(force: Bool) async {
        isLoading = true
        errorMessage = nil
        let key = LeagueDataCache.standingsKey(league.id)
        if !force, let cached = LeagueDataCache.load(LeagueDataCache.Standings.self, key: key) {
            standings = cached.rows
            teamsById = Dictionary(cached.teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            lastRefreshed = cached.date
            isLoading = false
            return
        }
        let client = league.client
        do {
            async let standingsReq = client.standings()
            async let teamsReq = client.teams()
            let (rows, teams) = try await (standingsReq, teamsReq)
            standings = rows
            teamsById = Dictionary(teams.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            let now = Date()
            lastRefreshed = now
            LeagueDataCache.save(LeagueDataCache.Standings(date: now, rows: rows, teams: teams), key: key)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct StandingRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let row: StandingDTO
    let team: TeamDTO?
    @State private var expanded = false

    private var isPad: Bool { sizeClass == .regular }
    private var nameFont: Font { isPad ? .title3 : .body }
    // Short name by default (consistent with Scores/Fixtures); tap to expand to
    // the full name for long ones (e.g. Wolverhampton).
    private var shortName: String { team?.shortName ?? team?.name ?? "Team \(row.teamId)" }
    private var fullName: String { team?.name ?? team?.shortName ?? "Team \(row.teamId)" }

    var body: some View {
        HStack(spacing: isPad ? 16 : 12) {
            Text("\(row.position)")
                .font(nameFont)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: isPad ? 40 : 28, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(expanded ? fullName : shortName)
                .font(nameFont)
                .lineLimit(expanded ? nil : 1)
            Spacer()
            // Played / Won / Drawn / Lost — labelled + larger on iPad.
            HStack(spacing: isPad ? 18 : 10) {
                stat("P", row.played)
                stat("W", row.won)
                stat("D", row.drawn)
                stat("L", row.lost)
            }
            Text("\(row.points)")
                .bold()
                .frame(width: isPad ? 48 : 32, alignment: .trailing)
                .font(nameFont)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
        .padding(.vertical, isPad ? 6 : 0)
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(isPad ? .caption2 : .system(size: 8))
                .foregroundStyle(.tertiary)
            Text("\(value)")
                .font(isPad ? .callout : .caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: isPad ? 24 : 14)
    }
}
