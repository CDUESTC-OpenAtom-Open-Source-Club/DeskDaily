import Foundation

// MARK: - Occurrence 日期计算工具（纯函数，可独立测试）
// v2.4 时间版地基：所有“某天的某个分钟”运算统一走这里，为跨午夜时段与未来视图铺路。

enum OccurrenceKit {
    /// "yyyy-MM-dd" → 该日正午的 Date（取正午避免夏令时边界误差）
    static func date(fromDayKey key: String, tz: TimeZone) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return cal.date(from: c)
    }

    /// dayKey 加/减 N 天
    static func dayKey(byAdding days: Int, toKey key: String, tz: TimeZone) -> String? {
        guard let base = date(fromDayKey: key, tz: tz) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let shifted = cal.date(byAdding: .day, value: days, to: base) else { return nil }
        return Store.dayKey(tz: tz, date: shifted)
    }

    /// dayKey 对应星期几（1=周日 … 7=周六，与 Calendar.weekday 一致）
    static func weekday(ofDayKey key: String, tz: TimeZone) -> Int? {
        guard let date = date(fromDayKey: key, tz: tz) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.weekday, from: date)
    }

    /// 从某天起连续枚举 N 个 dayKey（含起始日；解析失败返回空）
    static func enumerateDays(fromKey key: String, count: Int, tz: TimeZone) -> [String] {
        guard count > 0 else { return [] }
        var result: [String] = []
        var current = key
        result.append(current)
        for _ in 1..<count {
            guard let next = dayKey(byAdding: 1, toKey: current, tz: tz) else { break }
            result.append(next)
            current = next
        }
        return result
    }

    /// 时段结束信息：endMinutes 可超过 1439（跨午夜），spillDays = 结束时间落在起始日后第几天
    static func endInfo(startMinutes: Int, duration: Int) -> (endMinutes: Int, crossesMidnight: Bool, spillDays: Int) {
        let end = startMinutes + duration
        let spill = end / 1440
        return (end, spill > 0, spill)
    }

    /// occurrence 的绝对触发时刻：dayKey 当天的 startMinutes（可为负或 ≥1440，按天数溢出换算）
    static func fireDate(dayKey: String, minutes: Int, tz: TimeZone) -> Date? {
        var dayOffset = minutes / 1440
        var minuteOfDay = minutes % 1440
        if minuteOfDay < 0 {
            minuteOfDay += 1440
            dayOffset -= 1
        }
        guard let base = date(fromDayKey: dayKey, tz: tz) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let shifted = cal.date(byAdding: .day, value: dayOffset, to: base) else { return nil }
        var c = cal.dateComponents([.year, .month, .day], from: shifted)
        c.hour = minuteOfDay / 60
        c.minute = minuteOfDay % 60
        c.timeZone = tz
        return cal.date(from: c)
    }

    /// 任务未来 N 天内活跃的 dayKey 列表（今天起，含今天；once 只返回其指定日）
    static func upcomingDays(for task: TaskItem, fromKey key: String, count: Int, tz: TimeZone) -> [String] {
        enumerateDays(fromKey: key, count: count, tz: tz).filter { day in
            guard let weekday = weekday(ofDayKey: day, tz: tz) else { return false }
            return task.repeatRule.isActive(on: day, weekday: weekday)
        }
    }

    /// 结束时刻所在的日子标签：跨午夜时返回 "次日 HH:mm" 用的偏移描述
    static func endLabel(startMinutes: Int, duration: Int) -> String? {
        let info = endInfo(startMinutes: startMinutes, duration: duration)
        guard info.crossesMidnight else { return nil }
        return info.spillDays == 1 ? "次日" : "+\(info.spillDays)天"
    }
}
