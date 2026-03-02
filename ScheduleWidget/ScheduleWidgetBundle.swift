//
//  ScheduleWidgetBundle.swift
//  ScheduleWidget
//
//  Created by Jody on 2026/3/2.
//

import WidgetKit
import SwiftUI

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        AllScheduleWidget()
        TodayScheduleWidget()
        NextClassWidget()
        RemainClassWidget()
    }
}
