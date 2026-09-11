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
check("dueDate 非法日期被拒", (try? AppDataValidator.validate(makeData {
    $0.sheets[0].tasks[0].dueDate = "2026-02-30"
})) == nil)
check("skippedDays 非法日期被拒", (try? AppDataValidator.validate(makeData {
    $0.sheets[0].tasks[0].skippedDays = ["2026/09/02"]
})) == nil)
check("旧 JSON 缺少新字段仍可解码", {
    let json = #"{"title":"旧任务","repeatRule":{"kind":0,"weekdays":[],"date":""},"createdOn":"2026-09-01","doneDays":["2026-09-02"]}"#.data(using: .utf8)!
    let task = try? JSONDecoder().decode(TaskItem.self, from: json)
    return task?.title == "旧任务" && task?.doneDays.contains("2026-09-02") == true
}())
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
check("daily 截止日当天仍活跃", {
    let task = TaskItem(title: "每日截止", repeatRule: RepeatRule(), createdOn: "2026-09-01", dueDate: "2026-09-05")
    return StatsCore.wasActive(task, onDay: "2026-09-05", weekday: 7)
}())
check("截止日次日不活跃", {
    let task = TaskItem(title: "每日截止", repeatRule: RepeatRule(), createdOn: "2026-09-01", dueDate: "2026-09-05")
    return !StatsCore.wasActive(task, onDay: "2026-09-06", weekday: 1)
}())
check("weekly 跳过指定日", {
    let task = TaskItem(title: "工作日跳过", repeatRule: RepeatRule.weekly([4]), createdOn: "2026-09-01", skippedDays: ["2026-09-02"])
    return !StatsCore.wasActive(task, onDay: "2026-09-02", weekday: 4)
}())
check("weekly 跳过指定日", {
    let task = TaskItem(title: "工作日跳过", repeatRule: RepeatRule.weekly([4]), createdOn: "2026-09-01", skippedDays: ["2026-09-02"])
    return !StatsCore.wasActive(task, onDay: "2026-09-02", weekday: 4)
}())
check("skip/unskip 数据状态", {
    var task = TaskItem(title: "跳过恢复", repeatRule: RepeatRule(), skippedDays: ["2026-09-02"])
    task.skippedDays.remove("2026-09-02")
    return !task.skippedDays.contains("2026-09-02") && task.doneDays.isEmpty
}())
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

// MARK: - CalendarService 日历纯函数（v2.5）

let calDay = "2026-09-02"

check("dayBounds 起点=北京时间 0 点", {
    guard let b = CalendarService.dayBounds(forDayKey: calDay, tz: beijing) else { return false }
    var c = Calendar(identifier: .gregorian); c.timeZone = beijing
    let s = c.dateComponents([.month, .day, .hour, .minute], from: b.start)
    return s.month == 9 && s.day == 2 && s.hour == 0 && s.minute == 0
}())
check("dayBounds 终点=北京时间 24 点（次日 0 点）", {
    guard let b = CalendarService.dayBounds(forDayKey: calDay, tz: beijing) else { return false }
    var c = Calendar(identifier: .gregorian); c.timeZone = beijing
    let e = c.dateComponents([.month, .day, .hour, .minute], from: b.end)
    return e.month == 9 && e.day == 3 && e.hour == 0 && e.minute == 0
}())
check("dayBounds 时区差异（北京 0 点比 UTC 0 点早 8 小时）", {
    guard let b1 = CalendarService.dayBounds(forDayKey: calDay, tz: beijing),
          let b2 = CalendarService.dayBounds(forDayKey: calDay, tz: utc) else { return false }
    return b1.start.timeIntervalSince(b2.start) == -8 * 3600
        && b1.end.timeIntervalSince(b2.end) == -8 * 3600
}())
check("dayBounds 非法 key 返回 nil", CalendarService.dayBounds(forDayKey: "2026/09/02", tz: beijing) == nil)

func calEvent(_ title: String, startMinutes: Int, durationMinutes: Int,
              dayKey: String = calDay, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: title, title: title,
                  start: OccurrenceKit.fireDate(dayKey: dayKey, minutes: startMinutes, tz: beijing)!,
                  end: OccurrenceKit.fireDate(dayKey: dayKey, minutes: startMinutes + durationMinutes, tz: beijing)!,
                  isAllDay: allDay)
}

let morningMeeting = calEvent("晨会", startMinutes: 9 * 60, durationMinutes: 60)  // 09:00-10:00
let todayEvents = [morningMeeting, calEvent("年假事项", startMinutes: 0, durationMinutes: 0, allDay: true)]

check("overlap 命中：9:30+30 与 09:00-10:00 重叠",
      CalendarService.overlappingEvent(startMinutes: 9 * 60 + 30, duration: 30, dayKey: calDay, tz: beijing,
                                       events: todayEvents)?.title == "晨会")
check("overlap 不命中：11:00+30 与上午事件无交集",
      CalendarService.overlappingEvent(startMinutes: 11 * 60, duration: 30, dayKey: calDay, tz: beijing,
                                       events: [morningMeeting]) == nil)
check("overlap 无时长按 30 分钟占用（9:45 命中 / 10:01 不命中）",
      CalendarService.overlappingEvent(startMinutes: 9 * 60 + 45, duration: nil, dayKey: calDay, tz: beijing,
                                       events: [morningMeeting]) != nil
      && CalendarService.overlappingEvent(startMinutes: 10 * 60 + 1, duration: nil, dayKey: calDay, tz: beijing,
                                          events: [morningMeeting]) == nil)
check("overlap 全天事件整日占用，返回首个命中",
      CalendarService.overlappingEvent(startMinutes: 23 * 60, duration: 30, dayKey: calDay, tz: beijing,
                                       events: todayEvents)?.title == "年假事项")

// 跨午夜候选：溢出部分忽略，只比对起始日当天
let lateNightEvent = calEvent("夜班", startMinutes: 23 * 60 + 45, durationMinutes: 30)  // 23:45-次日00:15
check("overlap 跨午夜候选 23:30+60 只比对当天，命中 23:45 事件",
      CalendarService.overlappingEvent(startMinutes: 23 * 60 + 30, duration: 60, dayKey: calDay, tz: beijing,
                                       events: [lateNightEvent]) != nil)
check("overlap 次日才开始的当天候选不命中",
      CalendarService.overlappingEvent(startMinutes: 23 * 60 + 30, duration: 60, dayKey: calDay, tz: beijing,
                                       events: [calEvent("次日会", startMinutes: 24 * 60 + 15, durationMinutes: 30)]) == nil)

// 跨午夜事件：夹到当天窗口参与比对（昨天 23:00-今天 01:00 → 今天按 [0, 60) 占用）
let overnightEvent = calEvent("通宵项目", startMinutes: 23 * 60, durationMinutes: 120, dayKey: "2026-09-01")
check("overlap 跨午夜事件今天 0:00-0:30 命中",
      CalendarService.overlappingEvent(startMinutes: 0, duration: 30, dayKey: calDay, tz: beijing,
                                       events: [overnightEvent]) != nil)
check("overlap 跨午夜事件今天 1:30 起不命中",
      CalendarService.overlappingEvent(startMinutes: 1 * 60 + 30, duration: 30, dayKey: calDay, tz: beijing,
                                       events: [overnightEvent]) == nil)

check("aiBusyText 单条格式", CalendarService.aiBusyText(events: [morningMeeting], tz: beijing) == "09:00-10:00 晨会")
check("aiBusyText 多行每行一条", CalendarService.aiBusyText(
    events: [morningMeeting, calEvent("专注开发", startMinutes: 14 * 60, durationMinutes: 90)],
    tz: beijing) == "09:00-10:00 晨会\n14:00-15:30 专注开发")
check("aiBusyText 全天事件标「全天」", CalendarService.aiBusyText(
    events: [calEvent("年假", startMinutes: 0, durationMinutes: 0, allDay: true)], tz: beijing) == "全天 年假")
check("aiBusyText 空返回空串", CalendarService.aiBusyText(events: [], tz: beijing) == "")
check("timeRangeText 全天显示「全天」",
      CalendarService.timeRangeText(for: calEvent("休假", startMinutes: 0, durationMinutes: 0, allDay: true),
                                    tz: beijing) == "全天")

// MARK: - 结果

print("")
if failures == 0 {
    print("全部 \(total) 项测试通过 ✅")
} else {
    print("\(failures)/\(total) 项失败 ❌")
    exit(1)
}
