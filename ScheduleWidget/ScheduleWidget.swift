//
//  ScheduleWidget.swift
//  ScheduleWidget
//
//  Created by Jody on 2026/3/2.
//

import WidgetKit
import SwiftUI
import EventKit
import os

private let scheduleLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Widgetly", category: "ScheduleData")

struct Course: Identifiable, Equatable {
    let id: String
    let name: String
    let location: String
    let time: String
    let weekday: Int // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let periodID: Int
    let validWeeks: Set<Int>

    var startMinutes: Int { totalMinutes(hour: startHour, minute: startMinute) }
    var endMinutes: Int { totalMinutes(hour: endHour, minute: endMinute) }
}

struct LoadedSchedule {
    let configuration: ScheduleConfiguration
    let profile: ScheduleProfile
    let courses: [Course]
}

private enum ScheduleData {
    static var configuration: ScheduleConfiguration {
        do {
            let configuration = try ScheduleStore.loadWidgetConfiguration()
            guard configuration.totalWeeks > 0,
                  !configuration.schedules.isEmpty,
                  Set(configuration.schedules.map(\.id)).count == configuration.schedules.count,
                  configuration.schedules.allSatisfy({ profile in
                      !profile.periods.isEmpty &&
                      profile.periods.allSatisfy({ period in
                          guard let start = period.startTime, let end = period.endTime else { return false }
                          return start < end
                      }) && Set(profile.periods.map(\.id)).count == profile.periods.count
                  }) else {
                throw ScheduleDataError.invalidConfiguration
            }
            return configuration
        } catch {
            scheduleLogger.error("Failed to load shared ScheduleData.json: \(String(describing: error), privacy: .public)")
            return .fallback
        }
    }

    static func loaded(for date: Date) -> LoadedSchedule {
        do {
            let currentConfiguration = configuration
            let profileID = currentConfiguration.scheduleSelection.scheduleID(on: date)
            guard let profile = currentConfiguration.schedules.first(where: { $0.id == profileID }) else {
                throw ScheduleDataError.invalidConfiguration
            }
            let courses = try currentConfiguration.courses.map { record -> Course in
                guard (1...7).contains(record.weekday),
                      record.validWeeks.allSatisfy({ (1...currentConfiguration.totalWeeks).contains($0) }),
                      let period = profile.periods.first(where: { $0.id == record.periodID }),
                      let periodStart = period.startTime, let periodEnd = period.endTime else {
                    throw ScheduleDataError.invalidCourse(record.id)
                }
                let start: ScheduleTime
                let end: ScheduleTime
                if record.startTime == nil && record.endTime == nil {
                    start = periodStart
                    end = periodEnd
                } else if let customStart = record.startTime.flatMap(ScheduleTime.init(string:)),
                          let customEnd = record.endTime.flatMap(ScheduleTime.init(string:)),
                          customStart < customEnd {
                    start = customStart
                    end = customEnd
                } else {
                    throw ScheduleDataError.invalidCourse(record.id)
                }
                return Course(id: record.id, name: record.name, location: record.location,
                              time: "\(start.string)-\(end.string)", weekday: record.weekday,
                              startHour: start.hour, startMinute: start.minute,
                              endHour: end.hour, endMinute: end.minute, periodID: record.periodID,
                              validWeeks: Set(record.validWeeks))
            }
            return LoadedSchedule(configuration: currentConfiguration, profile: profile, courses: courses)
        } catch {
            scheduleLogger.error("Invalid schedule selection or course data: \(String(describing: error), privacy: .public)")
            return LoadedSchedule(configuration: configuration, profile: .fallback, courses: [])
        }
    }
}

private enum ScheduleDataError: Error {
    case invalidConfiguration
    case invalidCourse(String)
}

private extension ScheduleConfiguration {
    static let fallback = ScheduleConfiguration(semesterStartDate: "2026-09-14", totalWeeks: 16,
        scheduleSelection: ScheduleSelection(mode: "seasonal", summerScheduleID: "summer", winterScheduleID: "winter",
            winterStartsOn: nil, summerStartsOn: nil,
            customScheduleID: nil, fallbackScheduleID: "fallback"), schedules: [.fallback], courses: [])
}

private extension ScheduleProfile {
    static let fallback = ScheduleProfile(id: "fallback", name: "Fallback", periods: [
        SchedulePeriod(id: 0, start: "08:00", end: "09:50")
    ])
}

var scheduleConfiguration: ScheduleConfiguration { ScheduleData.configuration }
var activeScheduleProfile: ScheduleProfile { ScheduleData.loaded(for: Date()).profile }
var configuredCourses: [Course] { ScheduleData.loaded(for: Date()).courses }

// MARK: - Timeline Provider
struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), courses: configuredCourses)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        let entry = ScheduleEntry(date: Date(), courses: configuredCourses)
        completion(entry)
    }

    //    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
    //        var entries: [ScheduleEntry] = []
    //        let currentDate = Date()
    //
    //        let entry = ScheduleEntry(date: currentDate, courses: configuredCourses)
    //        entries.append(entry)
    //
    //        let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
    //        let timeline = Timeline(entries: entries, policy: .after(nextUpdateDate))
    //        completion(timeline)
    //    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [ScheduleEntry] = []
        let currentDate = Date()
        let calendar = Calendar.current


        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: currentDate)
        guard let startOfMinute = calendar.date(from: components) else {
            completion(Timeline(entries: [], policy: .atEnd))
            return
        }

        // 一次性生成未来 60 分钟的 Entry（这叫预载）
        // 从下一分钟的0秒开始算，确保每一分钟都在整点刷新
        for minuteOffset in 0..<60 {
            guard let entryDate = calendar.date(byAdding: .minute, value: minuteOffset + 1, to: startOfMinute) else { continue }

            // 这里的 courses 依然用你的数据
            let entry = ScheduleEntry(date: entryDate, courses: ScheduleData.loaded(for: entryDate).courses)
            entries.append(entry)
        }

        // 政策改为 .atEnd：这 60 个用完了再来找我
        let timeline = Timeline(entries: entries, policy: .atEnd)
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
    course.periodID
}

func getSlotTimeString(for slot: Int) -> String {
    guard let period = activeScheduleProfile.periods.first(where: { $0.id == slot }),
          let start = period.startTime, let end = period.endTime else { return "0:00-0:00" }
    return "\(start.string)-\(end.string)"
}

func getFreeTimeString(for slot: Int) -> String {
    let periods = activeScheduleProfile.periods.sorted { $0.id < $1.id }
    guard let index = periods.firstIndex(where: { $0.id == slot }),
          let periodEnd = periods[index].endTime else { return "0:00-0:00" }
    let start = index == 0 ? periods[index].startTime : periods[index - 1].endTime
    let end = index + 1 < periods.count ? periods[index + 1].startTime : periodEnd
    guard let start, let end else { return "0:00-0:00" }
    return "\(start.string)-\(end.string)"
}

func getFreeTimeMinutes(for slot: Int) -> [Int] {
    let periods = activeScheduleProfile.periods.sorted { $0.id < $1.id }
    guard let index = periods.firstIndex(where: { $0.id == slot }),
          let periodEnd = periods[index].endTime else { return [0, 0] }
    let start = index == 0 ? periods[index].startTime : periods[index - 1].endTime
    let end = index + 1 < periods.count ? periods[index + 1].startTime : periodEnd
    guard let start, let end else { return [0, 0] }
    return [start.minutes, end.minutes]
}

func isStartOfFreeBlock(_ slot: Int, dayCourses: [Course]) -> Bool {
    if dayCourses.contains(where: { getSlotIndex(for: $0) == slot }) { return false }
    let periods = activeScheduleProfile.periods.sorted { $0.id < $1.id }
    guard let index = periods.firstIndex(where: { $0.id == slot }) else { return false }
    if index == 0 { return true }
    let previousSlot = periods[index - 1].id
    return dayCourses.contains(where: { getSlotIndex(for: $0) == previousSlot })
}

func getFreeBlockSpan(startingAt slot: Int, dayCourses: [Course]) -> Int {
    let periods = activeScheduleProfile.periods.sorted { $0.id < $1.id }
    guard let index = periods.firstIndex(where: { $0.id == slot }) else { return 0 }
    var span = 0
    for period in periods[index...] {
        if dayCourses.contains(where: { getSlotIndex(for: $0) == period.id }) { break }
        span += 1
    }
    return span
}

func getFreeBlockEndSlot(startingAt slot: Int, span: Int) -> Int {
    let periods = activeScheduleProfile.periods.sorted { $0.id < $1.id }
    guard let index = periods.firstIndex(where: { $0.id == slot }), span > 0,
          index + span <= periods.count else { return slot }
    return periods[index + span - 1].id
}

func getCurrentWeek(for date: Date) -> Int {
    let calendar = Calendar.current
    let dateParts = scheduleConfiguration.semesterStartDate.split(separator: "-").compactMap { Int($0) }
    guard dateParts.count == 3,
          let semesterStart = calendar.date(from: DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2])) else { return 1 }
    let startOfSemester = calendar.startOfDay(for: semesterStart)
    let startOfDayDate = calendar.startOfDay(for: date)

    let componentsDiff = calendar.dateComponents([.day], from: startOfSemester, to: startOfDayDate)
    guard let days = componentsDiff.day, days >= 0 else { return 1 }
    let week = (days / 7) + 1
    return week <= scheduleConfiguration.totalWeeks ? week : scheduleConfiguration.totalWeeks + 1
}

func getTodaysCourses(from courses: [Course], for date: Date) -> [Course] {
    let currentWeekday = Calendar.current.component(.weekday, from: date)
    let currentWeek = getCurrentWeek(for: date)
    return courses.filter { $0.weekday == currentWeekday && $0.validWeeks.contains(currentWeek) }
        .sorted { $0.startMinutes < $1.startMinutes }
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
        $0.startMinutes > currentMins
    }
    .sorted { $0.startMinutes < $1.startMinutes }

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
        }.sorted { $0.startMinutes < $1.startMinutes }

        if !nextDayCourses.isEmpty {
            return nextDayCourses
        }
    }

    return []
}

func getCurrentCourse(from courses: [Course], for date: Date) -> Course? {
    let currentWeekday = Calendar.current.component(.weekday, from: date)
    let currentWeek = getCurrentWeek(for: date)
    let currentHour = Calendar.current.component(.hour, from: date)
    let currentMinute = Calendar.current.component(.minute, from: date)
    let currentMins = totalMinutes(hour: currentHour, minute: currentMinute)

    let todayCourses = courses.filter {
        $0.weekday == currentWeekday &&
        $0.validWeeks.contains(currentWeek) &&
        $0.startMinutes <= currentMins && $0.endMinutes > currentMins
    }

    return todayCourses.first

}

func getNextCalendarEvent(for date: Date = Date()) -> EKEvent? {
    let store = EKEventStore()

    let status = EKEventStore.authorizationStatus(for: .event)
    var isAuthorized = false
    #if compiler(>=5.9)
    if #available(iOS 17.0, macOS 14.0, *) {
        isAuthorized = (status == .fullAccess || status == .authorized)
    } else {
        isAuthorized = (status == .authorized)
    }
    #else
    isAuthorized = (status == .authorized)
    #endif

    guard isAuthorized else { return nil }

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    guard let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) else {
        return nil
    }

    let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
    let events = store.events(matching: predicate)
    // Filter for events that haven't started yet and are not all-day
    let upcomingEvents = events.filter { $0.startDate > date && !$0.isAllDay }

    // Return the next event by sorting
    return upcomingEvents.sorted { $0.startDate < $1.startDate }.first
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
            let currentWeekDay = Calendar.current.component(.weekday, from: entry.date)
            let currentHour = Calendar.current.component(.hour, from: entry.date)
            let currentMinute = Calendar.current.component(.minute, from: entry.date)
            let currentMins = totalMinutes(hour: currentHour, minute: currentMinute)

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
                            ForEach(activeScheduleProfile.periods.sorted { $0.id < $1.id }.map(\.id), id: \.self) { slot in
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
                                                            .font(.system(size: 11))
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(2)
                                                    }
                                                }
                                                .padding(2)
                                                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                                                .background(Color.blue.opacity( day == currentWeekDay && course.startMinutes <= currentMins && course.endMinutes > currentMins ? 0.4 : 0.15))
                                                .cornerRadius(4)
                                            } else if isStartOfFreeBlock(slot, dayCourses: dayCourses) {
                                                let span = getFreeBlockSpan(startingAt: slot, dayCourses: dayCourses)
                                                let endSlot = getFreeBlockEndSlot(startingAt: slot, span: span)
                                                let height = geo.size.height * CGFloat(span) + 4 * CGFloat(span - 1)
//                                                var startStr = getSlotTimeString(for: slot).components(separatedBy: "-").first ?? ""
//                                                var endStr = getSlotTimeString(for: slot + span - 1).components(separatedBy: "-").last ?? ""

                                                let startStr = getFreeTimeString(for: slot).components(separatedBy: "-").first ?? ""
                                                let endStr = getFreeTimeString(for: endSlot).components(separatedBy: "-").last ?? ""

//                                                let startStr = slotTimeStart == "14:00" ? "12:00" : slotTimeStart
//                                                let endStr = slotTimeEnd == "12:00" ? "14:00" : slotTimeEnd
                                                let startMin = getFreeTimeMinutes(for: slot).first ?? 0

                                                let endMin = getFreeTimeMinutes(for: endSlot).last ?? 0


                                             //  let isInTime = afterStartTime && beforeEndTime



                                                VStack(alignment: .center, spacing: 1) {
                                                    Text(startStr)
                                                    if family == .systemLarge {
                                                        Text("-")
                                                    }
                                                    Text(endStr)
                                                }
                                                .font(.system(size: family == .systemLarge ? 13 : 9, weight: .semibold))
                                                .foregroundColor(.green.opacity(0.7))
                                                .padding(1)
                                                .frame(width: geo.size.width, height: height)
                                                .background(Color.green.opacity(day == currentWeekDay && currentMins >= startMin && currentMins < endMin ? 0.4 : 0.15))
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
        let todaysCourses = getRemainingCourses(from: entry.courses, for: entry.date)
        let isConstrainedHeight = family == .systemSmall || family == .systemMedium
        let useVeryCompact = isConstrainedHeight && todaysCourses.count > 3
        let useCompact = isConstrainedHeight || todaysCourses.count > 4

        VStack(alignment: .leading, spacing: useVeryCompact ? 2 : 4) {
            HStack {
                Text(family == .systemSmall ? "Remain" : "Remaining Classes")
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .foregroundColor(.secondary)
                Spacer()



            }
            .padding(.bottom, 2)

            if todaysCourses.isEmpty {
                Spacer()
                Text("No upcoming classes")
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

struct TimeWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let remaining = getRemainingCourses(from: entry.courses, for: entry.date)
        let current = getCurrentCourse(from: entry.courses, for: entry.date)

        VStack(alignment: .center, spacing: 4) {
            Text("Timer")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)

            if remaining.isEmpty && current == nil {
                Spacer()
                Text("Done")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                if family == .systemSmall {
                    if let CurrentCourse = current{
                        Spacer()
                        let target = Calendar.current.date(bySettingHour: CurrentCourse.endHour, minute: CurrentCourse.endMinute, second: 0, of: entry.date) ?? entry.date
                        // 修复计算基准：统一使用 entry.date 而不是 Date()，这样配合 timeline 的正点刷新就不会多/少一分钟
                        let diff = Calendar.current.dateComponents([.hour, .minute], from: entry.date, to: target)

                        if #available(iOS 16.0, *) {
                            Text("\(diff.hour ?? 0):\(String(format: "%02d", diff.minute ?? 0))")
                                .font(.system(size: 36, weight: .bold, design: .default))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.spring(), value: entry.date)
                        } else {
                            Text("\(diff.hour ?? 0):\(String(format: "%02d", diff.minute ?? 0))")
                                .font(.system(size: 36, weight: .bold, design: .default))
                                .monospacedDigit()
                                .animation(.spring(), value: entry.date)
                        }
                        Spacer()
                        Text("Dismiss").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        // 当前休息，但是马上有课
                        Spacer()
                        let target = Calendar.current.date(bySettingHour: (totalMinutes(hour: remaining.first!.startHour, minute: remaining.first!.startMinute))/60, minute: (totalMinutes(hour: remaining.first!.startHour, minute: remaining.first!.startMinute))%60 , second: 0, of: entry.date) ?? entry.date
                        let diff = Calendar.current.dateComponents([.hour, .minute], from: entry.date, to: target)

                        if #available(iOS 16.0, *) {
                            Text("\(diff.hour ?? 0):\(String(format: "%02d", diff.minute ?? 0))")
                                .font(.system(size: 36, weight: .bold, design: .default))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.spring(), value: entry.date)
                        } else {
                            Text("\(diff.hour ?? 0):\(String(format: "%02d", diff.minute ?? 0))")
                                .font(.system(size: 36, weight: .bold, design: .default))
                                .monospacedDigit()
                                .animation(.spring(), value: entry.date)
                        }
                        Spacer()
                        Text(remaining.first!.name).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
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
            let remaining = getRemainingCourses(from: entry.courses, for: entry.date)

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

struct TimerWidget: Widget {
    let kind: String = "TimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            let remaining = getRemainingCourses(from: entry.courses, for: entry.date)
            let current = getCurrentCourse(from: entry.courses, for: entry.date)
         //   let isTransparent = remaining.isEmpty && current == nil

            if #available(iOS 17.0, macOS 14.0, *) {

                    TimeWidgetEntryView(entry: entry)
                        .containerBackground(.fill.tertiary, for: .widget)

            } else {
                TimeWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.clear)
            }
        }
        .configurationDisplayName("Timer")
        .description("See countdown to next Class & dismissal.")
        .supportedFamilies([.systemSmall])
    }
}


// MARK: - Previews
//struct ScheduleWidget_Previews2: PreviewProvider {
//    static var previews: some View {
//        Group {
//            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("All Schedule - Medium")
//
//            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemLarge))
//                .previewDisplayName("All Schedule - Large")
//
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemSmall))
//                .previewDisplayName("Today - Small")
//
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("Today - Medium")
//
//            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemLarge))
//                .previewDisplayName("Today - Large")
//
//            NextClassWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemSmall))
//                .previewDisplayName("Next Class - Small")
//
//            NextClassWidgetEntryView(entry: ScheduleEntry(date: .now, courses: configuredCourses))
//                .previewContext(WidgetPreviewContext(family: .systemMedium))
//                .previewDisplayName("Next Class - Medium")
//        }
//    }
//}

// MARK: - Previews
#if os(iOS)
@available(iOS 17.0, *)
struct ScheduleWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1. 全部课程表 - 中尺寸
            AllScheduleWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: configuredCourses))
                .containerBackground(for: .widget) { // 预览专用，不影响你原代码
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("All Schedule - Medium")

            // 2. 今日课程 - 中尺寸
            TodayScheduleWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: configuredCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Today - Medium")

            TimeWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: configuredCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Time - Small")


            // 3. 下一节课 - 中尺寸
            NextClassWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: configuredCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Next Class - Medium")

            // 2. 今日课程 - 中尺寸
            RemainClassWidgetEntryView(entry: ScheduleEntry(date: Date(), courses: configuredCourses))
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Remain - Medium")

        }
    }
}
#endif
