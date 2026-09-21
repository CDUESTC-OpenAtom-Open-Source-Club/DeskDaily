using System.Text.RegularExpressions;

namespace DeskDaily.Core;

public class ValidationException : Exception
{
    public ValidationException(string message) : base(message) { }
}

/// <summary>与 Mac 版 TaskItem.validate 对应的时段校验（v2.4 起允许跨午夜，时长 ≤600）。</summary>
public static class TaskItemValidator
{
    public static void Validate(int? remindAt, int? duration)
    {
        if (remindAt is not null && (remindAt.Value < 0 || remindAt.Value > 1439))
            throw new ValidationException("提醒时间必须在 00:00 至 23:59 之间");
        if (duration is not null && (duration.Value < 1 || duration.Value > 600))
            throw new ValidationException("时段时长必须在 1 至 600 分钟之间");
    }
}

/// <summary>与 Mac 版 AppDataValidator 对应的结构校验（v2.5 口径，含 dueDate/skippedDays）。</summary>
public static class AppDataValidator
{
    public const int CurrentSchemaVersion = 2;

    private static readonly Regex DayPattern = new(@"^\d{4}-\d{2}-\d{2}$", RegexOptions.Compiled);
    private static readonly Regex ColorPattern = new(@"^[0-9A-Fa-f]{6}$", RegexOptions.Compiled);

    public static AppData Validate(AppData data)
    {
        if (data.SchemaVersion > CurrentSchemaVersion)
            throw new ValidationException($"数据版本 {data.SchemaVersion} 高于当前支持版本，未加载该文件");

        // 失效/缺失的 activeSheetId 归一化到第一张表
        if (data.ActiveSheetId is null || data.Sheets.All(s => s.Id != data.ActiveSheetId))
            data.ActiveSheetId = data.Sheets.FirstOrDefault()?.Id;

        var sheetIds = new HashSet<Guid>();
        foreach (var sheet in data.Sheets)
        {
            if (sheet.Id == Guid.Empty || !sheetIds.Add(sheet.Id))
                throw new ValidationException($"计划表 {sheet.Id}：UUID 为空或重复");
            var name = sheet.Name.Trim();
            if (name.Length == 0 || name.Length > 12)
                throw new ValidationException($"计划表 {sheet.Id}：名称不能为空且不能超过 12 个字符");
            if (ColorPattern.IsMatch(sheet.ColorHex) == false)
                throw new ValidationException($"计划表 {sheet.Id}：主题色必须是 6 位十六进制颜色");
            ValidateTasks(sheet.Tasks);
        }
        return data;
    }

    private static void ValidateTasks(IEnumerable<TaskItem> tasks)
    {
        var ids = new HashSet<Guid>();
        foreach (var task in tasks)
        {
            if (task.Id == Guid.Empty || !ids.Add(task.Id))
                throw new ValidationException($"任务 {task.Id}：UUID 为空或重复");
            var title = task.Title.Trim();
            if (title.Length == 0 || title.Length > 60)
                throw new ValidationException($"任务 {task.Id}：标题不能为空且不能超过 60 个字符");
            TaskItemValidator.Validate(task.RemindAt, task.DurationMinutes);
            if (task.DueDate is not null && (DayPattern.IsMatch(task.DueDate) == false || !ValidDay(task.DueDate)))
                throw new ValidationException($"任务 {task.Id}：截止日期必须是有效的 yyyy-MM-dd");
            if (task.SkippedDays.Any(k => DayPattern.IsMatch(k) == false || !ValidDay(k)))
                throw new ValidationException($"任务 {task.Id}：跳过日期必须是有效的 yyyy-MM-dd");
            switch (task.RepeatRule.Kind)
            {
                case RepeatKind.Daily:
                    break;
                case RepeatKind.Weekly:
                    if (task.RepeatRule.Weekdays.Count == 0 || task.RepeatRule.Weekdays.Any(d => d is < 1 or > 7))
                        throw new ValidationException($"任务 {task.Id}：每周规则必须选择 1 至 7 且至少一天");
                    break;
                case RepeatKind.Once:
                    if (DayPattern.IsMatch(task.RepeatRule.Date) == false || !ValidDay(task.RepeatRule.Date))
                        throw new ValidationException($"任务 {task.Id}：一次性日期必须是有效的 yyyy-MM-dd");
                    break;
            }
        }
    }

    private static bool ValidDay(string value) =>
        DateTime.TryParseExact(value, "yyyy-MM-dd",
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out _);
}
