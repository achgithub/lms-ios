import SwiftUI

enum FixtureFormat {
    static let iso = ISO8601DateFormatter()
    static func kickoffDate(_ string: String) -> Date? { iso.date(from: string) }
}

/// Compact fixture row: home tile/TLA · v · away TLA/tile, with the kick-off
/// date + time and matchday stacked on the trailing edge (info only).
struct FixtureLabel: View {
    let fixture: FixtureDTO
    let teamsById: [Int: TeamDTO]

    private func tla(_ id: Int) -> String { teamsById[id]?.tla ?? "\(id)" }

    var body: some View {
        HStack(spacing: 8) {
            TeamTile(tla: teamsById[fixture.homeTeamId]?.tla, size: .small)
            Text(tla(fixture.homeTeamId)).font(.caption.weight(.semibold)).frame(width: 36, alignment: .leading)
            Text("v").font(.caption2).foregroundStyle(.secondary)
            Text(tla(fixture.awayTeamId)).font(.caption.weight(.semibold)).frame(width: 36, alignment: .leading)
            TeamTile(tla: teamsById[fixture.awayTeamId]?.tla, size: .small)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let date = FixtureFormat.kickoffDate(fixture.kickoff) {
                    Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                }
                if let matchday = fixture.matchday {
                    Text("MD \(matchday)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
