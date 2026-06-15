//
//  LMSApp.swift
//  LMS
//

import SwiftUI
import SwiftData

@main
struct LMSApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [Game.self, Player.self, Round.self, Pick.self, RosterMember.self, PlayerGroup.self])
    }
}
