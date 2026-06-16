import SwiftUI

enum FixtureFormat {
    static let iso = ISO8601DateFormatter()
    static func kickoffDate(_ string: String) -> Date? { iso.date(from: string) }
}

/// Compact, text-only fixture row: home name · v · away name, with the kick-off
/// date + time and matchday stacked on the trailing edge (info only).
struct FixtureLabel: View {
    let fixture: FixtureDTO
    let teamsById: [Int: TeamDTO]

    private func name(_ id: Int) -> String {
        teamsById[id]?.shortName ?? teamsById[id]?.name ?? "Team \(id)"
    }
    private var kickoff: Date? { FixtureFormat.kickoffDate(fixture.kickoff) }

    var body: some View {
        HStack(spacing: 8) {
            Text(name(fixture.homeTeamId))
                .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1)
            Text("v").font(.caption2).foregroundStyle(.secondary)
            Text(name(fixture.awayTeamId))
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            VStack(alignment: .trailing, spacing: 1) {
                if let kickoff {
                    Text(kickoff, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(kickoff, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                }
                if let matchday = fixture.matchday {
                    Text("MD \(matchday)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 74, alignment: .trailing)
        }
        .font(.callout)
    }
}
