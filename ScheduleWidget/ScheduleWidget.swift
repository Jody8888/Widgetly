//
//  ScheduleWidget.swift
//  ScheduleWidget
//
//  Created by Jody on 2026/3/2.
//

import WidgetKit
import SwiftUI
struct Course: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let location: String
    let time: String
    let weekday: Int // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    let startHour: Int
    let startMinute: Int
    let validWeeks: Set<Int>
}

// Dummy data for testing
let sampleCourses: [Course] = [
    // Monday
    Course(name: "高等数学", location: "中2-1200", time: "14:00-15:50", weekday: 2, startHour: 14, startMinute: 0, validWeeks: Set(1...16)),
    Course(name: "近代史纲要", location: "主楼C-205", time: "16:10-18:00", weekday: 2, startHour: 16, startMinute: 10, validWeeks: Set(1...16)),
    Course(name: "音乐&AI", location: "东2-362", time: "19:10-21:00", weekday: 2, startHour: 19, startMinute: 10, validWeeks: Set(1...16)),
    
    // Tuesday
    Course(name: "大学物理", location: "中3-3325", time: "8:00-9:50", weekday: 3, startHour: 8, startMinute: 0, validWeeks: Set(1...16)),
    Course(name: "大物实验", location: "仲英楼-B305", time: "10:10-12:00", weekday: 3, startHour: 10, startMinute: 10, validWeeks: Set(2...16)),
    Course(name: "程序设计", location: "主楼C-306", time: "14:00-15:50", weekday: 3, startHour: 14, startMinute: 0, validWeeks: Set([1,2,3,5,6,8,9,11,13,14])),
    Course(name: "微电子导论", location: "主楼C-206", time: "16:10-18:00", weekday: 3, startHour: 16, startMinute: 10, validWeeks: Set(9...16)),
    Course(name: "大学物理", location: "未安排地点", time: "19:10-21:00", weekday: 3, startHour: 19, startMinute: 10, validWeeks: Set([4,8,12,16])),

    // Wednesday
    Course(name: "高等数学", location: "中2-1200", time: "10:10-12:00", weekday: 4, startHour: 10, startMinute: 10, validWeeks: Set(1...16)),
    Course(name: "高等数学", location: "中2-1200", time: "16:10-18:00", weekday: 4, startHour: 16, startMinute: 10, validWeeks: Set([16])),

    // Thursday
    Course(name: "英语写作", location: "外文楼A-412", time: "10:10-12:00", weekday: 5, startHour: 10, startMinute: 10, validWeeks: Set(1...16)),
    Course(name: "大学物理", location: "中3-3325", time: "14:00-15:50", weekday: 5, startHour: 14, startMinute: 0, validWeeks: Set(1...16)),
    Course(name: "逻辑力量", location: "主楼A-102", time: "19:10-21:00", weekday: 5, startHour: 19, startMinute: 10, validWeeks: Set(1...8)),

    // Friday
    Course(name: "高等数学", location: "中2-1200", time: "8:00-9:50", weekday: 6, startHour: 8, startMinute: 0, validWeeks: Set(1...16)),
    Course(name: "极限飞盘", location: "东南足球场", time: "10:10-12:00", weekday: 6, startHour: 10, startMinute: 10, validWeeks: Set(1...16))
]

// MARK: - Timeline Provider
struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), courses: sampleCourses)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        let entry = ScheduleEntry(date: Date(), courses: sampleCourses)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [ScheduleEntry] = []
        let currentDate = Date()
        
        let entry = ScheduleEntry(date: currentDate, courses: sampleCourses)
        entries.append(entry)

        let nextUpdateDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdateDate))
        completion(timeline)
    }
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let courses: [Course]
}

// MARK: - Helpers
func getWeekdayShortName(weekday: Int) -> String {
    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    guard weekday >= 1 && weekday <= 7 else { return "" }
    return names[weekday - 1]
}

func totalMinutes(hour: Int, minute: Int) -> Int { return hour * 60 + minute }

func getSlotIndex(for course: Course) -> Int {
    switch course.startHour {
    case 0...9: return 0     // 8:00
    case 10...12: return 1   // 10:10
    case 13...14: return 2   // 14:00
    case 15...17: return 3   // 16:10
    case 18...23: return 4   // 19:10
    default: return 5
    }
}

func getSlotTimeString(for slot: Int) -> String {
    switch slot {
    case 0: return "8:00-9:50"
    case 1: return "10:10-12:00"
    case 2: return "14:00-15:50"
    case 3: return "16:10-18:00"
    case 4: return "19:10-21:00"
    default: return "0:00-0:00"
    }
}

func isStartOfFreeBlock(_ slot: Int, dayCourses: [Course]) -> Bool {
    if dayCourses.contains(where: { getSlotIndex(for: $0) == slot }) { return false }
    if slot == 0 { return true }
    return dayCourses.contains(where: { getSlotIndex(for: $0) == slot - 1 })
}

func getFreeBlockSpan(startingAt slot: Int, dayCourses: [Course]) -> Int {
    var span = 0
    for i in slot..<5 {
        if dayCourses.contains(where: { getSlotIndex(for: $0) == i }) { break }
        span += 1
    }
    return span
}

func getCurrentWeek(for date: Date) -> Int {
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 2
    guard let semesterStart = calendar.date(from: components) else { return 1 }
    let startOfSemester = calendar.startOfDay(for: semesterStart)
    let startOfDayDate = calendar.startOfDay(for: date)
    
    let componentsDiff = calendar.dateComponents([.day], from: startOfSemester, to: startOfDayDate)
    guard let days = componentsDiff.day, days >= 0 else { return 1 }
    
    return (days / 7) + 1
}

func getTodaysCourses(from courses: [Course], for date: Date) -> [Course] {
    let currentWeekday = Calendar.current.component(.weekday, from: date)
    let currentWeek = getCurrentWeek(for: date)
    return courses.filter { $0.weekday == currentWeekday && $0.validWeeks.contains(currentWeek) }
        .sorted { totalMinutes(hour: $0.startHour, minute: $0.startMinute) < totalMinutes(hour: $1.startHour, minute: $1.startMinute) }
}

func getRemainingCourses(from courses: [Course], for date: Date) -> [Course] {
    let currentWeekday = Calendar.current.component(.weekday, from: date)
    let currentWeek = getCurrentWeek(for: date)
    let currentHour = Calendar.current.component(.hour, from: date)
    let currentMinute = Calendar.current.component(.minute, from: date)
    let currentMins = totalMinutes(hour: currentHour, minute: currentMinute)
    
    let todayCourses = courses.filter { 
        $0.weekday == currentWeekday && 
        $0.validWeeks.contains(currentWeek) &&
        totalMinutes(hour: $0.startHour, minute: $0.startMinute) > currentMins 
    }
    .sorted { totalMinutes(hour: $0.startHour, minute: $0.startMinute) < totalMinutes(hour: $1.startHour, minute: $1.startMinute) }
    
    //if !todayCourses.isEmpty {
        return todayCourses
   // }
    
    for offset in 1...14 {
        let nextDate = Calendar.current.date(byAdding: .day, value: offset, to: date)!
        let nextWeekday = Calendar.current.component(.weekday, from: nextDate)
        let nextWeek = getCurrentWeek(for: nextDate)
        
        let nextDayCourses = courses.filter { 
            $0.weekday == nextWeekday &&
            $0.validWeeks.contains(nextWeek)
        }.sorted { totalMinutes(hour: $0.startHour, minute: $0.startMinute) < totalMinutes(hour: $1.startHour, minute: $1.startMinute) }
        
        if !nextDayCourses.isEmpty {
            return nextDayCourses
        }
    }
    
    return []
}

// MARK: - Views

struct CourseRowView: View {
    let course: Course
    var isCompact: Bool = false
    var isVeryCompact: Bool = false
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: isVeryCompact ? 0 : 2) {
                Text(course.name)
                    .font(isCompact ? .system(size: isVeryCompact ? 10 : 12, weight: .bold) : .headline)
                    .lineLimit(1)
                Text(course.location)
                    .font(isCompact ? .system(size: isVeryCompact ? 8 : 10) : .subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(course.time)
                .font(isCompact ? .system(size: isVeryCompact ? 8 : 10, weight: .bold) : .caption)
                .foregroundColor(.blue)
                .lineLimit(1)
        }
        .padding(.vertical, isCompact ? (isVeryCompact ? 0 : 2) : 4)
    }
}

// 1. All Schedule Widget UI
struct AllScheduleWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(spacing: 6) {
            if family == .systemLarge {
                Text("Weekly Schedule")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let currentWeek = getCurrentWeek(for: entry.date)
            // Calendar grid style Mon-Fri
            HStack(alignment: .top, spacing: 4) {
                ForEach(2...6, id: \.self) { day in
                    let dayCourses = entry.courses.filter { 
                        $0.weekday == day && $0.validWeeks.contains(currentWeek) 
                    }
                    
                    VStack(spacing: 4) {
                        Text(getWeekdayShortName(weekday: day))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        
                        VStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { slot in
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(
                                        GeometryReader { geo in
                                            if let course = dayCourses.first(where: { getSlotIndex(for: $0) == slot }) {
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(course.name)
                                                        .font(.system(size: family == .systemLarge ? 14 : 12, weight: .semibold))
                                                        .lineLimit(family == .systemLarge ? 2 : 1)
                                                        .minimumScaleFactor(0.8)
                                                    if family == .systemLarge {
                                                        Text(course.location)
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(2)
                                                    }
                                                }
                                                .padding(2)
                                                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                                                .background(Color.blue.opacity(0.15))
                                                .cornerRadius(4)
                                            } else if isStartOfFreeBlock(slot, dayCourses: dayCourses) {
                                                let span = getFreeBlockSpan(startingAt: slot, dayCourses: dayCourses)
                                                let height = geo.size.height * CGFloat(span) + 4 * CGFloat(span - 1)
//                                                var startStr = getSlotTimeString(for: slot).components(separatedBy: "-").first ?? ""
//                                                var endStr = getSlotTimeString(for: slot + span - 1).components(separatedBy: "-").last ?? ""
                                               
                                                let slotTimeStart = getSlotTimeString(for: slot).components(separatedBy: "-").first ?? ""
                                                let slotTimeEnd = getSlotTimeString(for: slot + span - 1).components(separatedBy: "-").last ?? ""

                                                let startStr = slotTimeStart == "14:00" ? "12:00" : slotTimeStart
                                                let endStr = slotTimeEnd == "12:00" ? "14:00" : slotTimeEnd
                                                
                                                VStack(alignment: .center, spacing: 1) {
                                                    Text(startStr)
                                                    if family == .systemLarge {
                                                        Text("-")
                                                    }
                                                    Text(endStr)
                                                }
                                                .font(.system(size: family == .systemLarge ? 13 : 9, weight: .semibold))
                                                .foregroundColor(.green.opacity(0.6))
                                                .padding(1)
                                                .frame(width: geo.size.width, height: height)
                                                .background(Color.green.opacity(0.15))
                                                .cornerRadius(4)
                                            }
                                        },
                                        alignment: .topLeading
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(-6)
    }
}

// 2. Today's Schedule Widget UI
struct TodayScheduleWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let todaysCourses = getTodaysCourses(from: entry.courses, for: entry.date)
        let isConstrainedHeight = family == .systemSmall || family == .systemMedium
        let useVeryCompact = isConstrainedHeight && todaysCourses.count > 3
        let useCompact = isConstrainedHeight || todaysCourses.count > 4
        
        VStack(alignment: .leading, spacing: useVeryCompact ? 2 : 4) {
            HStack {
                Text("Today")
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(getWeekdayShortName(weekday: Calendar.current.component(.weekday, from: entry.date)))
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .bold()
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 2)
            
            if todaysCourses.isEmpty {
                Spacer()
                Text("No classes today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else if family == .systemMedium && todaysCourses.count > 3 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(todaysCourses) { course in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text(course.location)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(course.time)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                Spacer(minLength: 0)
            } else {
                ForEach(todaysCourses) { course in
                    CourseRowView(course: course, isCompact: useCompact, isVeryCompact: useVeryCompact)
                    if course.id != todaysCourses.last?.id {
                        Divider().padding(.vertical, useVeryCompact ? -4 : (useCompact ? -2 : 0))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}



// 3. Next Class Widget UI
struct NextClassWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let remaining = getRemainingCourses(from: entry.courses, for: entry.date)
        
        VStack(alignment: family == .systemSmall ? .center : .leading, spacing: 4) {
            Text(family == .systemSmall ? "Next" : "Remaining Classes")
                .font(family == .systemSmall ? .subheadline : .subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)
            
            if remaining.isEmpty {
                Spacer()
                Text("No upcoming classes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                if family == .systemSmall {
                    if let nextCourse = remaining.first {
                        Spacer()
                        VStack(alignment: .center, spacing: 4) {
                            Text(nextCourse.name)
                                .font(.system(size: 20, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(nextCourse.location)
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.top,10)
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(nextCourse.time)
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }
                } else {
                    let limit = family == .systemMedium ? 3 : 6
                    let displayCourses = Array(remaining.prefix(limit))
                    
                    Spacer()
                    ForEach(displayCourses) { course in
                        CourseRowView(course: course, isCompact: false)
                        if course.id != displayCourses.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct RemainClassWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let remaining = getRemainingCourses(from: entry.courses, for: entry.date)
        
        VStack(alignment: family == .systemSmall ? .center : .leading, spacing: 4) {
            Text(family == .systemSmall ? "Remain" : "Remaining Classes")
                .font(family == .systemSmall ? .subheadline : .subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)
            
            if remaining.isEmpty {
                Spacer()
                Text("No upcoming classes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                if family == .systemSmall {
                   
                    let useVeryCompact = remaining.count > 3
                 //   let useCompact = isConstrainedHeight || remaining.count > 4
                 //   let limit = 3
                    let displayCourses = remaining
                    
                    Spacer()
                    ForEach(displayCourses) { course in
                        CourseRowView(course: course,isCompact: true, isVeryCompact: useVeryCompact)
                        if course.id != displayCourses.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                   // let limit = family == .systemMedium ? 3 : 6
                  
                   // let displayCourses = Array(remaining.prefix(limit))
                    
                    let isConstrainedHeight = family == .systemMedium
                    let useVeryCompact = isConstrainedHeight && remaining.count > 3
                    let useCompact = isConstrainedHeight || remaining.count > 4
                    let displayCourses = remaining
                    Spacer()
                    ForEach(displayCourses) { course in
                        CourseRowView(course: course, isCompact: useCompact,isVeryCompact: useVeryCompact)
                        if course.id != displayCourses.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}


// MARK: - Widgets
struct AllScheduleWidget: Widget {
    let kind: String = "AllScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                AllScheduleWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                AllScheduleWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.clear)
            }
        }
        .configurationDisplayName("All Schedule")
        .description("View all your classes.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayScheduleWidget: Widget {
    let kind: String = "TodayScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                TodayScheduleWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TodayScheduleWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.clear)
            }
        }
        .configurationDisplayName("Today's Schedule")
        .description("View your classes for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NextClassWidget: Widget {
    let kind: String = "NextClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                NextClassWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                NextClassWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.clear)
            }
        }
        .configurationDisplayName("Next")
        .description("See what class is coming up next.")
        .supportedFamilies([.systemSmall])
    }
}

struct RemainClassWidget: Widget {
    let kind: String = "RemainClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, macOS 14.0, *) {
                RemainClassWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                RemainClassWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.clear)
            }
        }
        .configurationDisplayName("Remain")
        .description("See your remaining courses today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}


// MARK: - Previews
//struct ScheduleWidget_Previews2: PreviewProvider {
//    static var previews: some View {
//        Group {
//            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("All Schedule - Medium")
//
//            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemLarge))
//                .previewDisplayName("All Schedule - Large")
//
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemSmall))
//                .previewDisplayName("Today - Small")
//            
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("Today - Medium")
//
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemLarge))
//                .previewDisplayName("Today - Large")
//
//            NextClassWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemSmall))
//                .previewDisplayName("Next Class - Small")
//            
//            NextClassWidgetEntryView(entry: ScheduleEntry(date: .now, courses: sampleCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("Next Class - Medium")
//        }
//    }
//}

// MARK: - Previews
@available(iOS 17.0, *)
struct ScheduleWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1. 全部课程表 - 中尺寸
            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: sampleCourses))
                .containerBackground(for: .widget) { // 预览专用，不影响你原代码
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("All Schedule - Medium")
            
            // 2. 今日课程 - 中尺寸
            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: sampleCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Today - Medium")
            
            
            // 3. 下一节课 - 中尺寸
            NextClassWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: sampleCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Next Class - Medium")
            
            // 2. 今日课程 - 中尺寸
            RemainClassWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: sampleCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Remain - Medium")
            
        }
    }
}

