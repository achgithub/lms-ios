import Foundation

/// Pure game-logic engine (port of the PWA's gameLogic.ts, spec §6.4/§6.5/§13c).
/// All methods are pure functions over the value types in EngineTypes.swift.
nonisolated enum GameEngine {

    // MARK: - Auto-assign (§6.4)

    /// Assign one team to each active player when the deadline passes.
    /// Standings-aware: the bottom-of-table available team is assigned first.
    /// Each player is independent — two players may receive the same team.
    /// Returns a map of player id → assigned team id. A player with no eligible
    /// team (repeats off and all fixture teams used) is omitted.
    static func autoAssign(_ input: AutoAssignInput) -> [UUID: Int] {
        let standingsKnown = input.fixtureTeams.contains { $0.position != nil }
        var assignments: [UUID: Int] = [:]
        for player in input.players {
            let ordered = orderedAvailableTeams(
                fixtureTeams: input.fixtureTeams,
                used: player.usedTeamIds,
                allowRepeats: input.allowRepeats,
                standingsKnown: standingsKnown
            )
            if let first = ordered.first {
                assignments[player.id] = first.id
            }
        }
        return assignments
    }

    /// The fixture teams ordered by assignment priority for one player.
    /// - Unused teams first; if repeats are allowed, used teams follow at the
    ///   bottom; if not, used teams are excluded entirely.
    /// - Within a group: by league position descending (position 20 / bottom
    ///   first) when standings are known, else alphabetically by name.
    static func orderedAvailableTeams(
        fixtureTeams: [TeamRef],
        used: Set<Int>,
        allowRepeats: Bool,
        standingsKnown: Bool
    ) -> [TeamRef] {
        let unused = fixtureTeams.filter { !used.contains($0.id) }
        let usedTeams = fixtureTeams.filter { used.contains($0.id) }

        func prioritised(_ teams: [TeamRef]) -> [TeamRef] {
            guard standingsKnown else {
                return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            return teams.sorted { lhs, rhs in
                switch (lhs.position, rhs.position) {
                case let (l?, r?): return l > r            // bottom of table first
                case (nil, _?): return false               // unknown positions last
                case (_?, nil): return true
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }

        return allowRepeats ? prioritised(unused) + prioritised(usedTeams) : prioritised(unused)
    }

    // MARK: - Eliminations (§6.5)

    /// A loss eliminates; win/draw/postponed survive. Unresolved (nil) is treated
    /// as surviving — a round should not be closed before results are known.
    static func computeEliminations(picks: [PickOutcome]) -> EliminationResult {
        var eliminated: [UUID] = []
        var surviving: [UUID] = []
        for pick in picks {
            switch pick.result {
            case .loss:
                eliminated.append(pick.playerId)
            case .win, .draw, .postponed, .none:
                surviving.append(pick.playerId)
            }
        }
        return EliminationResult(eliminatedPlayerIds: eliminated, survivingPlayerIds: surviving)
    }

    /// True when everyone still active was eliminated in the same round (§13c.4).
    static func isAllEliminated(activeBefore: Int, eliminatedThisRound: Int) -> Bool {
        activeBefore > 0 && eliminatedThisRound >= activeBefore
    }

    // MARK: - Tie / all-eliminated resolution (§13c)

    /// Whether the team pool is exhausted for the whole tied group — i.e. every
    /// tied player has already used every team in the league(s). When true, a
    /// "roll the week" must reopen their pool so they can keep picking.
    static func poolExhausted(usedTeamCounts: [Int], totalTeams: Int) -> Bool {
        guard !usedTeamCounts.isEmpty, totalTeams > 0 else { return false }
        return usedTeamCounts.allSatisfy { $0 >= totalTeams }
    }
}
