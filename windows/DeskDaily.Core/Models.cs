namespace DeskDaily.Core;

// MARK: - 数据模型（与 Mac 版 data.json schemaVersion=2 契约对齐）

public enum RepeatKind
{
    Daily = 0,
    Once = 1,
    Weekly = 2
}

public class RepeatRule
{
    public RepeatKind Kind { get; set; } = RepeatKind.Daily;
    /// <summary>1=周日 … 7=周六（与 Calendar.weekday 语义一致）</summary>
    public HashSet<int> Weekdays { get; set; } = new();
    public string Date { get; set; } = "";

    public static RepeatRule Once(string date) => new() { Kind = RepeatKind.Once, Date = date };

    public static RepeatRule Weekly(IEnumerable<int> days) => new() { Kind = RepeatKind.Weekly, Weekdays = new HashSet<int>(days) };

    public bool IsActiveOn(string dayKey, int weekday) => Kind switch
    {
        RepeatKind.Daily => true,
        RepeatKind.Once => Date == dayKey,
        RepeatKind.Weekly => Weekdays.Contains(weekday),
        _ => false
    };
}

public class TaskItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public int? RemindAt { get; set; }           // 开始时间，当天分钟数
    public int? DurationMinutes { get; set; }    // 时段时长（可跨午夜，≤600）
    public RepeatRule RepeatRule { get; set; } = new();
    public string CreatedOn { get; set; } = "";
    public HashSet<string> DoneDays { get; set; } = new(StringComparer.Ordinal);
    public string? DueDate { get; set; }         // 截止日期（yyyy-MM-dd，null=无）
    public HashSet<string> SkippedDays { get; set; } = new(StringComparer.Ordinal); // 跳过的 occurrence 起始日

    /// <summary>occurrence 是否有效（展示/提醒/统计统一口径），均以起始日为准。</summary>
    public bool IsActiveOn(string dayKey, int weekday) =>
        RepeatRule.IsActiveOn(dayKey, weekday)
        && (DueDate is null || string.CompareOrdinal(dayKey, DueDate) <= 0)
        && !SkippedDays.Contains(dayKey);
}

public class PlanSheet
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string ColorHex { get; set; } = "";
    public List<TaskItem> Tasks { get; set; } = new();
}

public class AppData
{
    public int SchemaVersion { get; set; } = 2;
    public List<PlanSheet> Sheets { get; set; } = new();
    public Guid? ActiveSheetId { get; set; }
}
