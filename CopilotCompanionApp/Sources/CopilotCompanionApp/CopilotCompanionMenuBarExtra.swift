//
//  CopilotCompanionMenuBarExtra.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/2/26.
//

import SwiftUI

public struct CopilotCompanionMenuBarExtra: Scene {
    @StateObject private var model = MenuBarModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(sessionCount: model.sessionsWaitingForUser.count)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let sessionCount: Int

    var body: some View {
        if sessionCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("\(sessionCount)")
            }
        } else {
            Image(systemName: "sparkles")
        }
    }
}
