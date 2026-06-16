import SwiftUI

/// The shareable round summary card (spec §13b.3). A pure function of
/// `SummaryData`; rendered to a `UIImage` via `ImageRenderer` for the share
/// sheet. Fixed 390pt width, height follows content.
struct SummaryCardView: View {
    let data: SummaryData

    // Palette (spec §13b.3 — dark, matches app theme).
    private let bg = Color(hex: "0F1A14")
    private let headerBar = Color(hex: "1A2E1E")
    private let textPrimary = Color(hex: "F5F5F5")
    private let textSecondary = Color(hex: "9CA3AF")
    private let accent = Color(hex: "F0C030")
    private let survivedGreen = Color(hex: "22C55E")
    private let eliminatedRed = Color(hex: "EF4444")

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionLabel
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            Divider().overlay(textSecondary.opacity(0.3))
            footer
        }
        .frame(width: 390)
        .background(bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            // App brand mark (not a club) — a clean accent badge.
            RoundedRectangle(cornerRadius: 12)
                .fill(accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Text("LMS")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(bg)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(data.gameName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                Text(data.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("ROUND").font(.system(size: 11, weight: .semibold)).foregroundStyle(textSecondary)
                Text("\(data.roundNumber)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(headerBar)
    }

    private var sectionLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(data.type.sectionLabel)
                .font(.system(size: 15, weight: .heavy)).tracking(2)
                .foregroundStyle(accent)
            Text(data.timestampLabel)
                .font(.system(size: 12)).foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch data.type {
        case .fixtures: fixturesContent
        case .picks:    picksContent
        case .results:  resultsContent
        case .outcome:  outcomeContent
        }
    }

    @ViewBuilder
    private var fixturesContent: some View {
        if data.fixtures.isEmpty {
            Text("No fixtures in this round.")
                .font(.system(size: 15)).foregroundStyle(textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.fixtures) { fixture in
                    HStack(spacing: 8) {
                        Text(fixture.homeName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1)
                        Text("v").font(.system(size: 13)).foregroundStyle(textSecondary)
                        Text(fixture.awayName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        if let kickoff = fixture.kickoff {
                            Text(kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.system(size: 11)).foregroundStyle(textSecondary)
                                .frame(width: 64, alignment: .trailing).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outcomeContent: some View {
        if let ending = data.outcome {
            VStack(alignment: .leading, spacing: 14) {
                Text(ending.headline)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(ending.listHeading)  (\(data.outcomePlayers.count))")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(textPrimary)
                    if data.outcomePlayers.isEmpty {
                        Text("—").font(.system(size: 15)).foregroundStyle(textSecondary)
                    } else {
                        namesLine(data.outcomePlayers, flag: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var picksContent: some View {
        if data.pickGroups.isEmpty {
            Text("No picks recorded for this round.")
                .font(.system(size: 15)).foregroundStyle(textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(data.pickGroups) { group in
                    HStack(alignment: .top, spacing: 12) {
                        if data.mode == .anonymous {
                            Text(group.teamName)
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(textPrimary)
                            Spacer(minLength: 8)
                            HStack(spacing: 4) {
                                Text("× \(group.count)")
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(accent)
                                if group.includesManager { managerFlag }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.teamName)
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(textPrimary)
                                namesLine(group.playerNames, flag: group.includesManager)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        // A single survivor means the game is won (last man standing) — show the
        // winner, not a non-existent next round. Zero survivors = all eliminated,
        // so there's no "through" line at all.
        let survived = data.survivors.count
        let won = survived == 1
        if data.mode == .anonymous {
            VStack(alignment: .leading, spacing: 16) {
                if survived > 0 {
                    Label {
                        Text(verbatim: won ? AppString("Winner")
                                           : AppString("\(survived) players through to Round \(data.nextRoundNumber)"))
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(textPrimary)
                    } icon: { Text(verbatim: won ? "🏆" : "✅") }
                    Divider().overlay(textSecondary.opacity(0.3))
                }
                Label {
                    Text(verbatim: eliminatedLine)
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(textPrimary)
                } icon: { Text(verbatim: "❌") }
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                if survived > 0 {
                    resultGroup(
                        icon: won ? "🏆" : "✅",
                        title: won ? AppString("Winner")
                                   : AppString("Through to Round \(data.nextRoundNumber) (\(survived))"),
                        names: data.survivors,
                        flagged: data.managerSurvived,
                        titleColor: won ? accent : survivedGreen
                    )
                }
                resultGroup(
                    icon: "❌",
                    title: AppString("Eliminated (\(data.eliminated.count))"),
                    names: data.eliminated,
                    flagged: data.managerEliminated,
                    titleColor: eliminatedRed
                )
            }
        }
    }

    private var eliminatedLine: String {
        data.eliminated.count == 1
            ? AppString("1 player eliminated")
            : AppString("\(data.eliminated.count) players eliminated")
    }

    @ViewBuilder
    private func resultGroup(icon: String, title: String, names: [String], flagged: Bool, titleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(icon)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(titleColor)
            }
            if names.isEmpty {
                Text("—").font(.system(size: 15)).foregroundStyle(textSecondary)
            } else {
                namesLine(names, flag: flagged).padding(.leading, 30)
            }
        }
    }

    /// A wrapping, comma-separated names line. Manager (if present) carries ⚑.
    private func namesLine(_ names: [String], flag: Bool) -> some View {
        (Text(names.joined(separator: ", "))
            + (flag ? Text("  ⚑").foregroundColor(accent) : Text("")))
            .font(.system(size: 14))
            .foregroundStyle(textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var managerFlag: some View {
        Text("⚑").font(.system(size: 15)).foregroundStyle(accent)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("\(data.activeCount) active")
                    .foregroundStyle(survivedGreen)
                Text("•").foregroundStyle(textSecondary)
                Text("\(data.eliminatedCount) eliminated")
                    .foregroundStyle(eliminatedRed)
            }
            .font(.system(size: 14, weight: .semibold))

            Text("\(SummaryData.watermarkDomain)  •  \(data.appName)")
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Previews

private extension SummaryData {
    static func sample(type: SummaryType, mode: AnonymityMode) -> SummaryData {
        SummaryData(
            type: type,
            mode: mode,
            leagueName: "Premier League",
            appName: "LMS: Premier League",
            gameName: "The Office Pool",
            roundNumber: 3,
            timestampLabel: type == .picks ? "Picks locked · Sat 16 Aug · 12:30"
                                            : "Full time · Sat 16 Aug · 17:00",
            pickGroups: [
                SummaryTeamGroup(teamId: 1, tla: "ARS", teamName: "Arsenal",
                                 playerNames: ["Andy", "Dave", "Pete", "Sarah"], includesManager: true),
                SummaryTeamGroup(teamId: 2, tla: "MUN", teamName: "Man Utd",
                                 playerNames: ["Chris", "Jake", "Lucy", "Mo", "Tom"], includesManager: false),
                SummaryTeamGroup(teamId: 3, tla: "CHE", teamName: "Chelsea",
                                 playerNames: ["Nina"], includesManager: false)
            ],
            survivors: ["Andy", "Dave", "Jake", "Lucy", "Nina", "Pete", "Sarah", "Tom"],
            eliminated: ["Chris", "Mo"],
            managerSurvived: true,
            managerEliminated: false,
            outcome: { if case .outcome(let e) = type { return e } else { return nil } }(),
            outcomePlayers: mode == .anonymous ? ["Player 1", "Player 4"] : ["Andy", "Nina"],
            fixtures: [
                SummaryFixture(id: 1, homeTla: "ARS", awayTla: "CHE", homeName: "Arsenal", awayName: "Chelsea", kickoff: .now),
                SummaryFixture(id: 2, homeTla: "MUN", awayTla: "LIV", homeName: "Man Utd", awayName: "Liverpool", kickoff: .now.addingTimeInterval(7200))
            ],
            activeCount: 8,
            eliminatedCount: 2
        )
    }
}

#Preview("Picks · Named") {
    SummaryCardView(data: .sample(type: .picks, mode: .named))
}

#Preview("Picks · Anonymous") {
    SummaryCardView(data: .sample(type: .picks, mode: .anonymous))
}

#Preview("Results · Named") {
    SummaryCardView(data: .sample(type: .results, mode: .named))
}

#Preview("Results · Anonymous") {
    SummaryCardView(data: .sample(type: .results, mode: .anonymous))
}

#Preview("Fixtures") {
    SummaryCardView(data: .sample(type: .fixtures, mode: .named))
}

#Preview("Outcome · Split") {
    SummaryCardView(data: .sample(type: .outcome(.split), mode: .named))
}

#Preview("Outcome · Roll the week · Anonymous") {
    SummaryCardView(data: .sample(type: .outcome(.rollWeek), mode: .anonymous))
}
