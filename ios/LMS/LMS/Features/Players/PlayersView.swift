import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The reusable player roster and groups hub (the second tab). Create players,
/// import them from CSV, and organise them into groups. Adding people to a game
/// happens inside the game (Games → Add Players), pulling from this roster.
struct PlayersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RosterMember.name) private var members: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    @State private var newName = ""
    @State private var newGroup = ""
    @State private var importing = false
    @State private var importGroupId: UUID?
    @State private var message: String?

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedGroup: String { newGroup.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section("Add a player") {
                    HStack {
                        TextField("Player name", text: $newName)
                            .onSubmit(addMember)
                        Button("Add", action: addMember)
                            .disabled(trimmedName.isEmpty || isDuplicateMember(trimmedName))
                    }
                    if isDuplicateMember(trimmedName) {
                        Text("‘\(trimmedName)’ is already in your players.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Import") {
                    if !groups.isEmpty {
                        Picker("Import into group", selection: $importGroupId) {
                            Text("No group").tag(UUID?.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(UUID?.some(group.id))
                            }
                        }
                    }
                    Button { importing = true } label: {
                        Label("Import CSV", systemImage: "doc.text")
                    }
                    // Single localized string key — can't wrap without changing the key.
                    // swiftlint:disable:next line_length
                    Text("One name per row. Add a group with `Name, Group`. Rows without one go to the selected import group above. `Name, Email` still works (email ignored).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let message {
                    Section { Text(message).font(.caption) }
                }

                Section("Groups (\(groups.count))") {
                    HStack {
                        TextField("New group name", text: $newGroup)
                            .onSubmit(addGroup)
                        Button("Add", action: addGroup)
                            .disabled(trimmedGroup.isEmpty || isDuplicateGroup(trimmedGroup))
                    }
                    ForEach(groups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(group.members.count)").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteGroups)
                }

                Section("Your players (\(members.count))") {
                    if members.isEmpty {
                        Text("No saved players yet. Add people here, then add them to a game.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            NavigationLink {
                                MemberGroupsView(member: member)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                    if !member.groups.isEmpty {
                                        Text(member.groups.map(\.name).sorted().joined(separator: ", "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteMembers)
                    }
                }
            }
            .navigationTitle("Players")
            .toolbar { if !members.isEmpty { EditButton() } }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    // MARK: Members

    private func isDuplicateMember(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return members.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addMember() {
        let name = trimmedName
        guard !name.isEmpty, !isDuplicateMember(name) else { return }
        context.insert(RosterMember(name: name))
        newName = ""
        message = nil
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets { context.delete(members[index]) }
    }

    // MARK: Groups

    private func isDuplicateGroup(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return groups.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addGroup() {
        let name = trimmedGroup
        guard !name.isEmpty, !isDuplicateGroup(name) else { return }
        context.insert(PlayerGroup(name: name))
        newGroup = ""
    }

    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets { context.delete(groups[index]) }
    }

    // MARK: CSV import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = AppString("Import failed: \(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                importRows(RosterCSV.parse(text))
            } catch {
                message = AppString("Couldn't read file: \(error.localizedDescription)")
            }
        }
    }

    /// Insert new (case-insensitively unique) members, resolve/create groups on
    /// the fly, and assign each member to its per-row group or the fallback.
    private func importRows(_ rows: [RosterCSV.Row]) {
        var membersByName = Dictionary(members.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var groupsByName = Dictionary(groups.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let fallbackGroupName = importGroupId.flatMap { id in groups.first { $0.id == id }?.name }

        func resolveGroup(_ name: String) -> PlayerGroup {
            let key = name.lowercased()
            if let existing = groupsByName[key] { return existing }
            let created = PlayerGroup(name: name)
            context.insert(created)
            groupsByName[key] = created
            return created
        }

        var added = 0, skipped = 0, assigned = 0
        for row in rows {
            let key = row.name.lowercased()
            let member: RosterMember
            if let existing = membersByName[key] {
                member = existing
                skipped += 1
            } else {
                member = RosterMember(name: row.name)
                context.insert(member)
                membersByName[key] = member
                added += 1
            }

            if let groupName = row.group ?? fallbackGroupName {
                let group = resolveGroup(groupName)
                if !member.groups.contains(where: { $0.id == group.id }) {
                    member.groups.append(group)
                    assigned += 1
                }
            }
        }

        var parts = [added == 1
                     ? AppString("Imported 1 new player")
                     : AppString("Imported \(added) new players")]
        if skipped > 0 {
            parts.append(skipped == 1
                         ? AppString("1 already existed")
                         : AppString("\(skipped) already existed"))
        }
        if assigned > 0 {
            parts.append(assigned == 1
                         ? AppString("1 group assignment")
                         : AppString("\(assigned) group assignments"))
        }
        // List separator is locale-aware; the parts are full clauses per language.
        message = parts.joined(separator: ", ") + "."
    }
}

/// Toggle which groups a roster member belongs to.
private struct MemberGroupsView: View {
    @Bindable var member: RosterMember
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    var body: some View {
        List {
            Section("Groups") {
                if groups.isEmpty {
                    Text("No groups yet — create one on the Players screen.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        Button {
                            toggle(group)
                        } label: {
                            HStack {
                                Text(group.name).foregroundStyle(.primary)
                                Spacer()
                                if isMember(of: group) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isMember(of group: PlayerGroup) -> Bool {
        member.groups.contains { $0.id == group.id }
    }

    private func toggle(_ group: PlayerGroup) {
        if let index = member.groups.firstIndex(where: { $0.id == group.id }) {
            member.groups.remove(at: index)
        } else {
            member.groups.append(group)
        }
    }
}
