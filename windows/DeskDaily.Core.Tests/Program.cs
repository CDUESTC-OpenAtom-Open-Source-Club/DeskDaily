using DeskDaily.Core;

// DeskDaily Windows 核心逻辑回归夹具（与 Tests/main.swift 的纯逻辑用例同源）
// 断言失败即退出码 1，供 windows-latest CI 执行。

var failures = 0;
var total = 0;

void Check(string name, bool condition)
{
    total++;
    if (condition)
    {
        Console.WriteLine($"✓ {name}");
    }
    else
    {
        failures++;
        Console.WriteLine($"✗ FAIL: {name}");
    }
}

var beijing = TimeZoneInfo.FindSystemTimeZoneById("Asia/Shanghai");
var utc = TimeZoneInfo.FindSystemTimeZoneById("UTC");

// MARK: - RepeatRule

var daily = new RepeatRule();
Check("daily 每天活跃", daily.IsActiveOn("2026-09-02", 4));
Check("daily 周末也活跃", daily.IsActiveOn("2026-09-05", 7));

var once = RepeatRule.Once("2026-09-02");
Check("once 仅指定日活跃", once.IsActiveOn("2026-09-02", 4));
Check("once 其他日不活跃", !once.IsActiveOn("2026-09-03", 5));

var weekdays = RepeatRule.Weekly(new[] { 2, 3, 4, 5, 6 });
Check("weekly 周一活跃(weekday=2)", weekdays.IsActiveOn("2026-08-31", 2));
Check("weekly 周日不活跃(weekday=1)", !weekdays.IsActiveOn("2026-09-06", 1));
Check("weekly 周六不活跃(weekday=7)", !weekdays.IsActiveOn("2026-09-05", 7));

// MARK: - TaskItemValidator

Check("无时间无时长合法", Record(() => TaskItemValidator.Validate(null, null)));
Check("23:30+29 当天内合法", Record(() => TaskItemValidator.Validate(23 * 60 + 30, 29)));
Check("23:31+30 跨午夜已解锁为合法", Record(() => TaskItemValidator.Validate(23 * 60 + 31, 30)));
Check("时间 1440 越界被拒", Reject(() => TaskItemValidator.Validate(1440, null)));
Check("时长 0 被拒", Reject(() => TaskItemValidator.Validate(600, 0)));
Check("时长 601 被拒", Reject(() => TaskItemValidator.Validate(600, 601)));

// MARK: - AppDataValidator

AppData MakeData(Action<AppData>? mutate = null)
{
    var data = new AppData();
    var sheet = new PlanSheet
    {
        Name = "测试表",
        ColorHex = "8B5CF6",
        Tasks = new List<TaskItem>
        {
            new()
            {
                Title = "任务A", RemindAt = 600, DurationMinutes = 30,
                RepeatRule = new RepeatRule(), CreatedOn = "2026-09-01"
            }
        }
    };
    data.Sheets.Add(sheet);
    data.ActiveSheetId = sheet.Id;
    mutate?.Invoke(data);
    return data;
}

Check("合法数据通过", Record(() => AppDataValidator.Validate(MakeData())));
Check("未来 schema 被拒", Reject(() => AppDataValidator.Validate(MakeData(d => d.SchemaVersion = 99))));
Check("非法颜色被拒", Reject(() => AppDataValidator.Validate(MakeData(d => d.Sheets[0].ColorHex = "XYZ"))));
Check("空标题被拒", Reject(() => AppDataValidator.Validate(MakeData(d => d.Sheets[0].Tasks[0].Title = "  "))));
Check("weekly 空 weekdays 被拒", Reject(() => AppDataValidator.Validate(MakeData(d =>
    d.Sheets[0].Tasks[0].RepeatRule = RepeatRule.Weekly(Array.Empty<int>())))));
Check("weekly weekday 越界被拒", Reject(() => AppDataValidator.Validate(MakeData(d =>
    d.Sheets[0].Tasks[0].RepeatRule = RepeatRule.Weekly(new[] { 0, 8 })))));
Check("once 非法日期被拒", Reject(() => AppDataValidator.Validate(MakeData(d =>
    d.Sheets[0].Tasks[0].RepeatRule = RepeatRule.Once("2026/09/02")))));
Check("dueDate 非法日期被拒", Reject(() => AppDataValidator.Validate(MakeData(d =>
    d.Sheets[0].Tasks[0].DueDate = "2026-02-30"))));
Check("skippedDays 非法日期被拒", Reject(() => AppDataValidator.Validate(MakeData(d =>
    d.Sheets[0].Tasks[0].SkippedDays.Add("2026/09/02")))));

bool ActiveSheetNormalized()
{
    var bad = MakeData(d => d.ActiveSheetId = Guid.NewGuid());
    var fixedData = AppDataValidator.Validate(bad);
    return fixedData.ActiveSheetId == fixedData.Sheets.First().Id;
}
Check("失效 activeSheetId 被归一化", ActiveSheetNormalized());

// MARK: - OccurrenceKit

Check("dayKey +1 天", OccurrenceKit.DayKeyByAdding(1, "2026-09-02", beijing) == "2026-09-03");
Check("dayKey -1 天跨月", OccurrenceKit.DayKeyByAdding(-1, "2026-09-01", beijing) == "2026-08-31");
Check("dayKey +1 跨年", OccurrenceKit.DayKeyByAdding(1, "2026-12-31", beijing) == "2027-01-01");
Check("weekday：2026-09-02 是周三(4)", OccurrenceKit.WeekdayOfDayKey("2026-09-02", beijing) == 4);
Check("枚举 7 天", OccurrenceKit.EnumerateDays("2026-09-02", 7, beijing).Count == 7);
Check("枚举首日是起始日", OccurrenceKit.EnumerateDays("2026-09-02", 7, beijing)[0] == "2026-09-02");

var endSameDay = OccurrenceKit.EndInfo(22 * 60, 60);
Check("22:00+60 当天结束", !endSameDay.CrossesMidnight && endSameDay.EndMinutes == 1380);
var endCross = OccurrenceKit.EndInfo(23 * 60, 90);
Check("23:00+90 跨午夜", endCross.CrossesMidnight && endCross.EndMinutes == 1470 && endCross.SpillDays == 1);

var endFire = OccurrenceKit.FireDate("2026-09-02", 1470, beijing);
Check("跨午夜结束时刻=次日00:30", endFire is not null &&
      OccurrenceKit.DayKey(beijing, endFire.Value) == "2026-09-03" &&
      endFire.Value.ToUniversalTime() == TimeZoneInfo.ConvertTimeToUtc(new DateTime(2026, 9, 3, 0, 30, 0), beijing));

var backFire = OccurrenceKit.FireDate("2026-09-03", -30, beijing);
Check("负分钟换算到前一天", backFire is not null &&
      backFire.Value.ToUniversalTime() == TimeZoneInfo.ConvertTimeToUtc(new DateTime(2026, 9, 2, 23, 30, 0), beijing));

var dailyTask = new TaskItem { Title = "每日", RepeatRule = new RepeatRule() };
var upcoming = OccurrenceKit.UpcomingDays(dailyTask, "2026-09-02", 7, beijing);
Check("每日任务未来 7 天全活跃", upcoming.Count == 7);
var weeklyTask = new TaskItem { Title = "工作日", RepeatRule = RepeatRule.Weekly(new[] { 2, 3, 4, 5, 6 }) };
Check("工作日任务未来 7 天命中 5 天", OccurrenceKit.UpcomingDays(weeklyTask, "2026-09-02", 7, beijing).Count == 5);
Check("结束标签：不跨天为 null", OccurrenceKit.EndLabel(600, 30) == null);
Check("结束标签：跨天为「次日」", OccurrenceKit.EndLabel(23 * 60 + 30, 60) == "次日");

// MARK: - 时区语义（同一天在北京时区是 09-02，UTC 是 09-01）

var cal = TimeZoneInfo.ConvertTimeToUtc(new DateTime(2026, 9, 1, 17, 30, 0), utc);
Check("北京时区 dayKey", OccurrenceKit.DayKey(beijing, cal) == "2026-09-02");
Check("UTC 时区 dayKey", OccurrenceKit.DayKey(utc, cal) == "2026-09-01");

// MARK: - StatsCore

var sheetA = new PlanSheet
{
    Name = "A", ColorHex = "8B5CF6",
    Tasks = new List<TaskItem>
    {
        new() { Title = "每日任务", RepeatRule = new RepeatRule(), CreatedOn = "2026-08-01",
                DoneDays = new HashSet<string>(StringComparer.Ordinal) { "2026-09-01", "2026-09-02" } },
        new() { Title = "工作日任务", RepeatRule = RepeatRule.Weekly(new[] { 2, 3, 4, 5, 6 }), CreatedOn = "2026-08-01",
                DoneDays = new HashSet<string>(StringComparer.Ordinal) { "2026-09-02" } },
        new() { Title = "仅一次", RepeatRule = RepeatRule.Once("2026-09-03"), CreatedOn = "2026-08-01" }
    }
};
var countsWed = StatsCore.DayCounts(new[] { sheetA }, "2026-09-02", 4);
Check("周三总数=2（每日+工作日）", countsWed.Total == 2);
Check("周三完成=2", countsWed.Done == 2);
var countsSat = StatsCore.DayCounts(new[] { sheetA }, "2026-09-05", 7);
Check("周六总数=1（仅每日）", countsSat.Total == 1);

var lateSheet = new PlanSheet
{
    Name = "B", ColorHex = "8B5CF6",
    Tasks = new List<TaskItem>
    {
        new() { Title = "后建任务", RepeatRule = new RepeatRule(), CreatedOn = "2026-09-10",
                DoneDays = new HashSet<string>(StringComparer.Ordinal) { "2026-09-01" } }
    }
};
Check("创建日晚于统计日不计入", StatsCore.DayCounts(new[] { lateSheet }, "2026-09-05", 7).Total == 0);

// v2.5 口径：跳过与截止
var skipTask = new TaskItem { Title = "跳过日", RepeatRule = new RepeatRule(), CreatedOn = "2026-09-01",
    SkippedDays = new HashSet<string>(StringComparer.Ordinal) { "2026-09-02" } };
Check("跳过日不计入分母", StatsCore.DayCounts(new[] { new PlanSheet { Name = "S", ColorHex = "8B5CF6", Tasks = { skipTask } } }, "2026-09-02", 4).Total == 0);
Check("非跳过日仍计入", StatsCore.DayCounts(new[] { new PlanSheet { Name = "S", ColorHex = "8B5CF6", Tasks = { skipTask } } }, "2026-09-03", 5).Total == 1);
var dueTask = new TaskItem { Title = "有截止", RepeatRule = new RepeatRule(), CreatedOn = "2026-09-01", DueDate = "2026-09-05" };
Check("截止日当天仍活跃", dueTask.IsActiveOn("2026-09-05", 7));
Check("截止日次日不活跃", !dueTask.IsActiveOn("2026-09-06", 1));

// MARK: - 结果

Console.WriteLine();
if (failures == 0)
{
    Console.WriteLine($"全部 {total} 项测试通过 ✅");
}
else
{
    Console.WriteLine($"{failures}/{total} 项失败 ❌");
    Environment.Exit(1);
}

static bool Record(Action action)
{
    try { action(); return true; }
    catch (ValidationException) { return false; }
}

static bool Reject(Action action)
{
    try { action(); return false; }
    catch (ValidationException) { return true; }
}
