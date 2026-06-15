import SwiftUI
import SwiftData

/// Add players to a game by picking from your reusable roster (managed on the
/// Players tab). Filter by group to quickly pull in the right set of people.
/// Creating/importing players now lives on the Players tab — this screen just adds.
struct AddPlayersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @Query(sort: \RosterMember.name) private var roster: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]
    let game: Game

    /// nil = no filter (all roster members).
    @State private var filterGroupId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if !managerTrimmed.isEmpty {
                    Section {
                        Button {
                            managerInGame ? removeManager() : addManager()
                        } label: {
                            HStack {
                                Text("\(managerTrimmed) (you)").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: managerInGame ? "minus.circle.fill" : "plus.circle")
                                    .foregroundStyle(managerInGame ? .red : .blue)
                            }
                        }
                    } header: {
                        Text("You")
                    } footer: {
                        Text(managerInGame
                             ? "You're playing — your pick shows on shared cards (⚑)."
                             : "You're not playing this game — no ⚑ on cards.")
                    }
                }

                if !groups.isEmpty {
                    Section("Filter") {
                        Picker("Group", selection: $filterGroupId) {
                            Text("All players").tag(UUID?.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(UUID?.some(group.id))
                            }
                        }
                    }
                }

                Section("Add from your players") {
                    if roster.isEmpty {
                        Text("No saved players yet. Add people on the Players tab first, then add them here.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if addable.isEmpty {
                        Text(filterGroupId == nil
                             ? "Everyone in your roster is already in this game."
                             : "Everyone in this group is already in this game.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button {
                            for member in addable { add(member) }
                        } label: {
                            Label("Add all (\(addable.count))", systemImage: "person.2.badge.plus")
                        }
                        ForEach(addable) { member in
                            Button {
                                add(member)
                            } label: {
                                HStack {
                                    Text(member.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("In this game (\(game.players.count))") {
                    if game.players.isEmpty {
                        Text("No players yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedPlayers) { Text($0.name) }
                    }
                }
            }
            .navigationTitle("Add Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func existingNames() -> Set<String> {
        Set(game.players.map { $0.name.lowercased() })
    }

    private var managerTrimmed: String { managerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var managerInGame: Bool {
        game.players.contains { $0.isManager } ||
        game.players.contains { $0.name.localizedCaseInsensitiveCompare(managerTrimmed) == .orderedSame }
    }

    /// Roster members matching the group filter, not already in the game, and not
    /// the manager (who is added via the dedicated "You" row so the ⚑ is set).
    private var addable: [RosterMember] {
        let inGame = existingNames()
        return roster.filter { member in
            guard !inGame.contains(member.name.lowercased()) else { return false }
            guard member.name.localizedCaseInsensitiveCompare(managerTrimmed) != .orderedSame else { return false }
            guard let filterGroupId else { return true }
            return member.groups.contains { $0.id == filterGroupId }
        }
    }

    private func add(_ member: RosterMember) {
        guard !existingNames().contains(member.name.lowercased()) else { return }
        let player = Player(name: member.name, game: game, entryNumber: game.nextEntryNumber)
        context.insert(player)
        game.players.append(player)
    }

    private func addManager() {
        guard !managerTrimmed.isEmpty, !managerInGame else { return }
        let player = Player(name: managerTrimmed, game: game, isManager: true,
                            entryNumber: game.nextEntryNumber)
        context.insert(player)
        game.players.append(player)
    }

    /// Remove the manager from this game (they're running it but not playing).
    private func removeManager() {
        for player in game.players where player.isManager
            || player.name.localizedCaseInsensitiveCompare(managerTrimmed) == .orderedSame {
            context.delete(player)
        }
    }
}
