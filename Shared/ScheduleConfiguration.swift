import Foundation

struct ScheduleTime: Codable, Comparable {
    let hour: Int
    let minute: Int

    init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    var minutes: Int { hour * 60 + minute }
    var string: String { String(format: "%02d:%02d", hour, minute) }
    static func < (lhs: ScheduleTime, rhs: ScheduleTime) -> Bool { lhs.minutes < rhs.minutes }
}

struct SchedulePeriod: Codable {
    let id: Int
    let start: String
    let end: String
    var startTime: ScheduleTime? { ScheduleTime(string: start) }
    var endTime: ScheduleTime? { ScheduleTime(string: end) }
}

struct ScheduleProfile: Codable {
    let id: String
    let name: String
    let periods: [SchedulePeriod]
}

struct ScheduleSelection: Codable {
    let mode: String
    let summerScheduleID: String
    let winterScheduleID: String
    let winterStartsOn: String?
    let summerStartsOn: String?
    let customScheduleID: String?
    let fallbackScheduleID: String

    func scheduleID(on date: Date, calendar: Calendar = .current) -> String {
        if mode == "custom" {
            return customScheduleID ?? fallbackScheduleID
        }
        guard mode == "seasonal",
              let winterStart = Self.monthDayKey(winterStartsOn),
              let summerStart = Self.monthDayKey(summerStartsOn),
              winterStart != summerStart else { return fallbackScheduleID }

        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return fallbackScheduleID }
        let today = month * 100 + day

        if summerStart < winterStart {
            return today >= summerStart && today < winterStart ? summerScheduleID : winterScheduleID
        }
        return today >= winterStart && today < summerStart ? winterScheduleID : summerScheduleID
    }

    func isValid(profileIDs: Set<String>) -> Bool {
        guard profileIDs.contains(fallbackScheduleID) else { return false }
        if mode == "custom" {
            return customScheduleID.map(profileIDs.contains) ?? false
        }
        guard mode == "seasonal",
              profileIDs.contains(summerScheduleID), profileIDs.contains(winterScheduleID) else { return false }
        switch (winterStartsOn, summerStartsOn) {
        case (nil, nil):
            return true
        case let (winter?, summer?):
            guard let winterKey = Self.monthDayKey(winter),
                  let summerKey = Self.monthDayKey(summer) else { return false }
            return winterKey != summerKey
        default:
            return false
        }
    }

    private static func monthDayKey(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        let maxDay = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard (1...maxDay).contains(day) else { return nil }
        return month * 100 + day
    }
}

struct CourseRecord: Codable {
    let id: String
    let name: String
    let location: String
    let weekday: Int
    let periodID: Int
    let startTime: String?
    let endTime: String?
    let validWeeks: [Int]
}

struct ScheduleConfiguration: Codable {
    let semesterStartDate: String
    let totalWeeks: Int
    let scheduleSelection: ScheduleSelection
    let schedules: [ScheduleProfile]
    let courses: [CourseRecord]

    func validate() throws {
        let startParts = semesterStartDate.split(separator: "-").compactMap { Int($0) }
        guard startParts.count == 3,
              (1...12).contains(startParts[1]),
              (1...31).contains(startParts[2]),
              totalWeeks > 0,
              !schedules.isEmpty else {
            throw ScheduleConfigurationError.invalidSemester
        }

        let profileIDs = Set(schedules.map(\.id))
        guard profileIDs.count == schedules.count,
              scheduleSelection.isValid(profileIDs: profileIDs) else {
            throw ScheduleConfigurationError.invalidScheduleSelection
        }

        for profile in schedules {
            let periods = profile.periods.sorted { $0.id < $1.id }
            guard !periods.isEmpty,
                  Set(periods.map(\.id)).count == periods.count else {
                throw ScheduleConfigurationError.invalidPeriods(profile.name)
            }
            var previousEnd: Int?
            for period in periods {
                guard let start = period.startTime, let end = period.endTime,
                      start < end, previousEnd.map({ start.minutes >= $0 }) ?? true else {
                    throw ScheduleConfigurationError.invalidPeriods(profile.name)
                }
                previousEnd = end.minutes
            }
        }

        let courseIDs = Set(courses.map(\.id))
        guard courseIDs.count == courses.count else {
            throw ScheduleConfigurationError.duplicateCourseID
        }
        for course in courses {
            guard !course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (1...7).contains(course.weekday),
                  !course.validWeeks.isEmpty,
                  course.validWeeks.allSatisfy({ (1...totalWeeks).contains($0) }),
                  schedules.allSatisfy({ $0.periods.contains(where: { $0.id == course.periodID }) }) else {
                throw ScheduleConfigurationError.invalidCourse(course.id)
            }
            switch (course.startTime, course.endTime) {
            case (nil, nil):
                break
            case let (start?, end?):
                guard let startTime = ScheduleTime(string: start),
                      let endTime = ScheduleTime(string: end), startTime < endTime else {
                    throw ScheduleConfigurationError.invalidCourse(course.id)
                }
            default:
                throw ScheduleConfigurationError.invalidCourse(course.id)
            }
        }
    }
}

enum ScheduleConfigurationError: LocalizedError {
    case invalidSemester
    case invalidScheduleSelection
    case invalidPeriods(String)
    case duplicateCourseID
    case invalidCourse(String)

    var errorDescription: String? {
        switch self {
        case .invalidSemester:
            return "学期起始日期、总周数或作息配置无效。"
        case .invalidScheduleSelection:
            return "季节切换配置或作息 ID 无效。"
        case .invalidPeriods(let name):
            return "“\(name)”中的时段格式错误、重叠或顺序无效。"
        case .duplicateCourseID:
            return "课程 id 重复。"
        case .invalidCourse(let id):
            return "课程 \(id) 的星期、周次、节次或自定义时间无效。"
        }
    }
}
