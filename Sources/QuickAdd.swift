import Foundation

// MARK: - 自然语言快速添加（纯本地解析，无网络请求）

/// parseQuickAdd 的结果：识别出的时间/时长/规则 + 剔除这些词后的干净标题
struct QuickAddParse: Equatable {
    var title: String = ""
    /// 提醒时间（当天分钟数）
    var remindMinutes: Int? = nil
    /// 时长（分钟）
    var duration: Int? = nil
    /// 重复规则（nil = 未识别到）
    var rule: RepeatRule? = nil
    /// 各识别项命中的原文片段：作为预览芯片的"移除签名"，
    /// 点 ✗ 后记录该片段，重新解析时同片段不再自动回填
    var timeToken: String? = nil
    var durationToken: String? = nil
    var ruleToken: String? = nil

    var matched: Bool { timeToken != nil || durationToken != nil || ruleToken != nil }
}

/// 中文快速添加解析，支持：
/// - 时间：`9:30` / `9点30` / `21时` / `9点半`，配 `早上/上午/中午/下午/傍晚/晚上/凌晨` 前缀；
///   `明早/明天早上/明晚/明天晚上/明天` → 仅明天（需要传 tomorrowKey）
/// - 时长：`45分钟` / `30分` / `30m` / `半小时`=30 / `一小时`=60 / `一个半小时`=90 / `2小时`=120
/// - 规则：`周二健身` / `星期三` / `每周五` → 每周指定日；`每天` → 每天
/// - 剩余干净文本作为标题
func parseQuickAdd(_ text: String, tomorrowKey: String? = nil) -> QuickAddParse {
    var result = QuickAddParse()
    var work = text
    var removals: [NSRange] = []

    // 把已识别的片段从工作串中替换成空格（避免中文里词与词相连）
    func flushRemovals() {
        guard !removals.isEmpty else { return }
        let ns = NSMutableString(string: work)
        for r in removals.sorted(by: { $0.location > $1.location }) {
            if r.location != NSNotFound, r.location + r.length <= ns.length {
                ns.replaceCharacters(in: r, with: " ")
            }
        }
        work = ns as String
        removals = []
    }

    let fullRange = NSRange(work.startIndex..., in: work)
    func substring(_ r: NSRange) -> String? {
        guard let range = Range(r, in: work) else { return nil }
        return String(work[range])
    }

    // 1) 时间：可选日期前缀 + 可选时段词 + 数字时间
    let timePattern = #"(明早|明天早上|明晚|明天晚上|明天)?\s*(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2})(?:[:：](\d{2})|[点时](半|\d{1,2})?分?)"#
    if let regex = try? NSRegularExpression(pattern: timePattern),
       let m = regex.firstMatch(in: work, range: fullRange), m.numberOfRanges >= 6 {
        func group(_ i: Int) -> String? {
            guard i < m.numberOfRanges else { return nil }
            return substring(m.range(at: i))
        }
        if let hourText = group(3), let literalHour = Int(hourText) {
            var hour = literalHour
            var minute = 0
            if let colon = group(4) {
                minute = Int(colon) ?? 0
            } else if let dot = group(5) {
                minute = dot == "半" ? 30 : (Int(dot) ?? 0)
            }
            let dayWord = group(1)
            var period = group(2)
            if period == nil, dayWord == "明晚" || dayWord == "明天晚上" { period = "晚上" }
            switch period {
            case "中午": if hour <= 10 { hour += 12 }          // 中午1点 → 13:00，中午12点 → 12:00
            case "下午", "傍晚": if hour <= 11 { hour += 12 }   // 下午2点 → 14:00
            case "晚上": hour = hour <= 11 ? hour + 12 : 0     // 晚上10点 → 22:00，晚上12点 → 0:00
            default: break                                       // 早上/上午/凌晨/无前缀按字面（9点 → 9:00）
            }
            if literalHour <= 23, minute <= 59 {
                result.remindMinutes = ((hour % 24) * 60 + minute) % 1440
                result.timeToken = substring(m.range)
                removals = [m.range]
                if dayWord != nil, let key = tomorrowKey {
                    result.rule = RepeatRule.once(date: key)
                    result.ruleToken = dayWord
                }
                flushRemovals()
            }
        }
    }

    // 2) 独立的"明天"（没有具体时间，如「明天交报告」）→ 仅明天
    if result.rule == nil, let key = tomorrowKey,
       let regex = try? NSRegularExpression(pattern: "明早|明天早上|明晚|明天晚上|明天"),
       let m = regex.firstMatch(in: work, range: NSRange(work.startIndex..., in: work)) {
        result.rule = RepeatRule.once(date: key)
        result.ruleToken = substring(m.range)
        removals = [m.range]
        flushRemovals()
    }

    // 3) 时长（按优先级取第一个命中的写法）
    let durationPatterns: [(String, (Double) -> Int)] = [
        ("一个半小时", { _ in 90 }),
        ("半小时", { _ in 30 }),
        ("一[个]?小时", { _ in 60 }),
        (#"(\d+(?:\.\d+)?)\s*[个]?小时"#, { Int(($0 * 60).rounded()) }),
        (#"(\d+)\s*分钟"#, { Int($0) }),
        (#"(\d+)\s*分"#, { Int($0) }),
        (#"(\d+)\s*m(?![A-Za-z0-9])"#, { Int($0) }),
    ]
    for (pattern, compute) in durationPatterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: work, range: NSRange(work.startIndex..., in: work)) else { continue }
        var value: Double = 1
        if m.numberOfRanges > 1, let text = substring(m.range(at: 1)), let d = Double(text) {
            value = d
        }
        let minutes = compute(value)
        if minutes >= 1 {
            result.duration = min(minutes, 600)
            result.durationToken = substring(m.range)
            removals = [m.range]
            flushRemovals()
        }
        break
    }

    // 4) 每天 / 周几 → 重复规则（词始终从标题剔除；规则只在尚未有规则时采纳）
    if let regex = try? NSRegularExpression(pattern: "每天"),
       let m = regex.firstMatch(in: work, range: NSRange(work.startIndex..., in: work)) {
        if result.rule == nil {
            result.rule = RepeatRule()
            result.ruleToken = "每天"
        }
        removals = [m.range]
        flushRemovals()
    }
    if let regex = try? NSRegularExpression(pattern: "(?:每周|星期|周)([一二三四五六日天])") {
        let weekdayMap: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        var days = Set<Int>()
        var tokens: [String] = []
        for m in regex.matches(in: work, range: NSRange(work.startIndex..., in: work)) {
            guard let text = substring(m.range(at: 1)), let wd = weekdayMap[text.first ?? " "] else { continue }
            days.insert(wd)
            tokens.append(substring(m.range) ?? "")
            removals.append(m.range)
        }
        if !days.isEmpty {
            if result.rule == nil {
                result.rule = RepeatRule.weekly(days)
                result.ruleToken = tokens.joined(separator: ",")
            }
            flushRemovals()
        }
    }

    // 5) 收尾：合并空格、去首尾杂 punctuation，得到干净标题
    let cleaned = work
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: CharacterSet(charactersIn: "，,、。·-—"))
    result.title = String(cleaned.prefix(60))
    return result
}
