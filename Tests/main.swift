// DeskDaily 核心逻辑测试（纯 Foundation 断言式，无 XCTest 依赖）
// 运行方式：Tests/run_tests.sh（编译所需源文件 + 本文件后执行）
// 覆盖：RepeatRule / TaskItem.validate / AppDataValidator / dayKey / AIClient 解析 / StatsCore 统计口径
import Foundation

var failures = 0
var total = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    total += 1
    if condition() {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ FAIL: \(name)")
    }
}

// MARK: - RepeatRule

let daily = RepeatRule()
check("daily 每天活跃", daily.isActive(on: "2026-09-02", weekday: 4))
check("daily 周末也活跃", daily.isActive(on: "2026-09-05", weekday: 7))

let once = RepeatRule.once(date: "2026-09-02")
check("once 仅指定日活跃", once.isActive(on: "2026-09-02", weekday: 4))
check("once 其他日不活跃", !once.isActive(on: "2026-09-03", weekday: 5))

let weekdays = RepeatRule.weekly([2, 3, 4, 5, 6])
check("weekly 周一活跃(weekday=2)", weekdays.isActive(on: "2026-08-31", weekday: 2))
check("weekly 周日不活跃(weekday=1)", !weekdays.isActive(on: "2026-09-06", weekday: 1))
check("weekly 周六不活跃(weekday=7)", !weekdays.isActive(on: "2026-09-05", weekday: 7))

// MARK: - TaskItem.validate

check("无时间无时长合法", (try? TaskItem.validate(remindAt: nil, duration: nil)) != nil)
check("23:30+29 当天内合法", (try? TaskItem.validate(remindAt: 23 * 60 + 30, duration: 29)) != nil)
check("23:31+30 跨午夜已解锁为合法", (try? TaskItem.validate(remindAt: 23 * 60 + 31, duration: 30)) != nil)
check("23:00+600 最大溢出仍合法", (try? TaskItem.validate(remindAt: 23 * 60, duration: 600)) != nil)
check("时间 1440 越界被拒", (try? TaskItem.validate(remindAt: 1440, duration: nil)) == nil)
check("时长 0 被拒", (try? TaskItem.validate(remindAt: 600, duration: 0)) == nil)
check("时长 601 被拒", (try? TaskItem.validate(remindAt: 600, duration: 601)) == nil)

// MARK: - AppDataValidator

func makeData(_ mutate: (inout AppData) -> Void) -> AppData {
    var data = AppData()
    let sheet = PlanSheet(name: "测试表", colorHex: "8B5CF6", tasks: [
        TaskItem(title: "任务A", remindAt: 600, durationMinutes: 30,
                 repeatRule: RepeatRule(), createdOn: "2026-09-01")
    ])
    data.sheets = [sheet]
    data.activeSheetId = sheet.id
    mutate(&data)
    return data
}

check("合法数据通过", (try? AppDataValidator.validate(makeData { _ in })) != nil)
check("未来 schema 被拒", (try? AppDataValidator.validate(makeData { $0.schemaVersion = 99 })) == nil)
check("非法颜色被拒", (try? AppDataValidator.validate(makeData { $0.sheets[0].colorHex = "XYZ" })) == nil)
check("空标题被拒", (try? AppDataValidator.validate(makeData { $0.sheets[0].tasks[0].title = "  " })) == nil)
check("weekly 空 weekdays 被拒", (try? AppDataValidator.validate(makeData {
    $0.sheets[0].tasks[0].repeatRule = RepeatRule.weekly([])
})) == nil)
check("weekly weekday 越界被拒", (try? AppDataValidator.validate(makeData {
    $0.sheets[0].tasks[0].repeatRule = RepeatRule.weekly([0, 8])
})) == nil)
check("once 非法日期被拒", (try? AppDataValidator.validate(makeData {
    $0.sheets[0].tasks[0].repeatRule = RepeatRule.once(date: "2026/09/02")
})) == nil)
check("失效 activeSheetId 被归一化", {
    let bad = makeData { $0.activeSheetId = UUID() }
    let fixed = try? AppDataValidator.validate(bad)
    return fixed?.activeSheetId == fixed?.sheets.first?.id
}())

// MARK: - dayKey / 时区语义

let beijing = TimeZone(identifier: "Asia/Shanghai")!
let utc = TimeZone(identifier: "UTC")!
// 2026-09-02 01:30 北京时间 = 2026-09-01 17:30 UTC：同一天在北京时区是 09-02，UTC 是 09-01
var cal = Calendar(identifier: .gregorian)
cal.timeZone = utc
let instant = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 17, minute: 30))!
check("北京时区 dayKey", Store.dayKey(tz: beijing, date: instant) == "2026-09-02")
check("UTC 时区 dayKey", Store.dayKey(tz: utc, date: instant) == "2026-09-01")

// MARK: - AIClient 解析与净化

check("HH:mm 解析", AIClient.minutes(fromHHMM: "09:30") == 570)
check("HH:mm 非法解析为 nil", AIClient.minutes(fromHHMM: "24:00") == nil)

let payload = #"[{"title":"晨间锻炼","remindAt":"07:30","repeatDaily":false,"durationMinutes":30},{"title":"阅读","remindAt":null,"repeatDaily":true}]"#
let tasks = AIClient.parseTasks(from: payload)
check("候选解析 2 项", tasks.count == 2)
check("候选字段正确", tasks[0].durationMinutes == 30 && tasks[1].repeatDaily && tasks[1].remindAt == nil)

let mixed = "安排如下：\n- 09:00 锻炼\n```json\n[{\"title\":\"X\",\"remindAt\":\"08:00\",\"repeatDaily\":true}]\n```"
let cleaned = AIClient.displayText(from: mixed)
check("净化保留自然语言", cleaned.contains("09:00 锻炼"))
check("净化去除 JSON", !cleaned.contains("remindAt") && !cleaned.contains("```"))

// MARK: - StatsCore 统计口径

let sheetA = PlanSheet(name: "A", colorHex: "8B5CF6", tasks: [
    TaskItem(title: "每日任务", repeatRule: RepeatRule(), createdOn: "2026-08-01",
             doneDays: ["2026-09-01", "2026-09-02"]),
    TaskItem(title: "工作日任务", repeatRule: RepeatRule.weekly([2, 3, 4, 5, 6]), createdOn: "2026-08-01",
             doneDays: ["2026-09-02"]),
    TaskItem(title: "仅一次", repeatRule: RepeatRule.once(date: "2026-09-03"), createdOn: "2026-08-01")
])
// 2026-09-02 是周三（weekday=4）
let countsWed = StatsCore.dayCounts(sheets: [sheetA], dayKey: "2026-09-02", weekday: 4)
check("周三总数=2（每日+工作日）", countsWed.total == 2)
check("周三完成=2", countsWed.done == 2)
// 2026-09-05 是周六（weekday=7）：每日活跃，工作日不活跃
let countsSat = StatsCore.dayCounts(sheets: [sheetA], dayKey: "2026-09-05", weekday: 7)
check("周六总数=1（仅每日）", countsSat.total == 1)
// createdOn 晚于统计日 → 不计入（历史公平性口径）
let lateSheet = PlanSheet(name: "B", colorHex: "8B5CF6", tasks: [
    TaskItem(title: "后建任务", repeatRule: RepeatRule(), createdOn: "2026-09-10", doneDays: ["2026-09-01"])
])
check("创建日晚于统计日不计入", StatsCore.dayCounts(sheets: [lateSheet], dayKey: "2026-09-05", weekday: 7).total == 0)

// MARK: - OccurrenceKit 日期工具

check("dayKey +1 天", OccurrenceKit.dayKey(byAdding: 1, toKey: "2026-09-02", tz: beijing) == "2026-09-03")
check("dayKey -1 天跨月", OccurrenceKit.dayKey(byAdding: -1, toKey: "2026-09-01", tz: beijing) == "2026-08-31")
check("dayKey +1 跨年", OccurrenceKit.dayKey(byAdding: 1, toKey: "2026-12-31", tz: beijing) == "2027-01-01")
check("weekday：2026-09-02 是周三(4)", OccurrenceKit.weekday(ofDayKey: "2026-09-02", tz: beijing) == 4)
check("枚举 7 天", OccurrenceKit.enumerateDays(fromKey: "2026-09-02", count: 7, tz: beijing).count == 7)
check("枚举首日是起始日", OccurrenceKit.enumerateDays(fromKey: "2026-09-02", count: 7, tz: beijing).first == "2026-09-02")

let endSameDay = OccurrenceKit.endInfo(startMinutes: 22 * 60, duration: 60)
check("22:00+60 当天结束", !endSameDay.crossesMidnight && endSameDay.endMinutes == 1380)
let endCross = OccurrenceKit.endInfo(startMinutes: 23 * 60, duration: 90)
check("23:00+90 跨午夜", endCross.crossesMidnight && endCross.endMinutes == 1470 && endCross.spillDays == 1)

// 触发时刻：23:00+90 的结束提醒应落在次日 00:30
if let endFire = OccurrenceKit.fireDate(dayKey: "2026-09-02", minutes: 1470, tz: beijing) {
    var c = Calendar(identifier: .gregorian); c.timeZone = beijing
    let comp = c.dateComponents([.month, .day, .hour, .minute], from: endFire)
    check("跨午夜结束时刻=次日00:30", comp.day == 3 && comp.hour == 0 && comp.minute == 30)
} else {
    check("跨午夜结束时刻=次日00:30", false)
}
// 负分钟（未来“次日”视图可能的相对表达）也能换算
if let backFire = OccurrenceKit.fireDate(dayKey: "2026-09-03", minutes: -30, tz: beijing) {
    var c = Calendar(identifier: .gregorian); c.timeZone = beijing
    let comp = c.dateComponents([.day, .hour, .minute], from: backFire)
    check("负分钟换算到前一天", comp.day == 2 && comp.hour == 23 && comp.minute == 30)
} else {
    check("负分钟换算到前一天", false)
}

let dailyTask = TaskItem(title: "每日", repeatRule: RepeatRule())
let upcoming = OccurrenceKit.upcomingDays(for: dailyTask, fromKey: "2026-09-02", count: 7, tz: beijing)
check("每日任务未来 7 天全活跃", upcoming.count == 7)
let weeklyTask = TaskItem(title: "工作日", repeatRule: RepeatRule.weekly([2, 3, 4, 5, 6]))
let workdays = OccurrenceKit.upcomingDays(for: weeklyTask, fromKey: "2026-09-02", count: 7, tz: beijing)
check("工作日任务未来 7 天命中 5 天", workdays.count == 5)
check("结束标签：不跨天为 nil", OccurrenceKit.endLabel(startMinutes: 600, duration: 30) == nil)
check("结束标签：跨天为「次日」", OccurrenceKit.endLabel(startMinutes: 23 * 60 + 30, duration: 60) == "次日")

// MARK: - 结果

print("")
if failures == 0 {
    print("全部 \(total) 项测试通过 ✅")
} else {
    print("\(failures)/\(total) 项失败 ❌")
    exit(1)
}
