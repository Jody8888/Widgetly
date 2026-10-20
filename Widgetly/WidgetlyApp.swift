//
//  WidgetlyApp.swift
//  Widgetly
//
//  Created by Jody on 2026/3/2.
//

import SwiftUI
import WidgetKit

@main
struct WidgetlyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    synchronizeScheduleFile()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                synchronizeScheduleFile()
            }
        }
    }

    private func synchronizeScheduleFile() {
        do {
            try ScheduleStore.synchronizeDocumentsToWidget()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NSLog("Unable to sync Documents/ScheduleData.json with the widget: %@", String(describing: error))
        }
    }
}
