using System.Text.RegularExpressions;

namespace DeskDaily.Core;

/// <summary>
/// Occurrence 日期计算工具的 C# 移植（与 Sources/OccurrenceKit.swift 对应）。
/// 所有“某天的某个分钟”运算统一走这里；跨午夜分钟数（≥1440 或负值）按天溢出换算。
/// </summary>
public static class OccurrenceKit
{
    /// <summary>"yyyy-MM-dd" → 该日正午的 UTC 时刻（取正午避免夏令时边界误差）。</summary>
    public static DateTime? DateFromDayKey(string key, TimeZoneInfo tz)
    {
        var parts = key.Split('-');
        if (parts.Length != 3
            || !int.TryParse(parts[0], out var y)
            || !int.TryParse(parts[1], out var m)
            || !int.TryParse(parts[2], out var d))
            return null;
        if (y is < 1 or > 9999 || m is < 1 or > 12 || d is < 1 or > 31) return null;
        var local = new DateTime(y, m, d, 12, 0, 0, DateTimeKind.Unspecified);
        try
        {
            return TimeZoneInfo.ConvertTimeToUtc(local, tz);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>UTC 时刻 → tz 时区的 dayKey（yyyy-MM-dd）。</summary>
    public static string DayKey(TimeZoneInfo tz, DateTime utc)
    {
        var local = TimeZoneInfo.ConvertTimeFromUtc(
            DateTime.SpecifyKind(utc, DateTimeKind.Utc), tz);
        return $"{local.Year:D4}-{local.Month:D2}-{local.Day:D2}";
    }

    /// <summary>dayKey 加/减 N 天，越界或解析失败返回 null。</summary>
    public static string? DayKeyByAdding(int days, string key, TimeZoneInfo tz)
    {
        var baseDate = DateFromDayKey(key, tz);
        if (baseDate is null) return null;
        return DayKey(tz, baseDate.Value.AddDays(days));
    }

    /// <summary>dayKey 对应星期几（1=周日 … 7=周六，与 Calendar.weekday 一致）；解析失败返回 null。</summary>
    public static int? WeekdayOfDayKey(string key, TimeZoneInfo tz)
    {
        var date = DateFromDayKey(key, tz);
        if (date is null) return null;
        var local = TimeZoneInfo.ConvertTimeFromUtc(
            DateTime.SpecifyKind(date.Value, DateTimeKind.Utc), tz);
        return ((int)local.DayOfWeek % 7) + 1;
    }

    /// <summary>从某天起连续枚举 N 个 dayKey（含起始日）。</summary>
    public static List<string> EnumerateDays(string fromKey, int count, TimeZoneInfo tz)
    {
        var result = new List<string>();
        if (count <= 0) return result;
        var current = fromKey;
        result.Add(current);
        for (var i = 1; i < count; i++)
        {
            var next = DayKeyByAdding(1, current, tz);
            if (next is null) break;
            result.Add(next);
            current = next;
        }
        return result;
    }

    /// <summary>时段结束信息：endMinutes 可超过 1439（跨午夜）。</summary>
    public static (int EndMinutes, bool CrossesMidnight, int SpillDays) EndInfo(int startMinutes, int duration)
    {
        var end = startMinutes + duration;
        var spill = end / 1440;
        return (end, spill > 0, spill);
    }

    /// <summary>occurrence 的绝对触发时刻（minutes 可为负或 ≥1440，按天溢出换算）。</summary>
    public static DateTime? FireDate(string dayKey, int minutes, TimeZoneInfo tz)
    {
        var dayOffset = (int)Math.Floor((decimal)minutes / 1440);
        var minuteOfDay = minutes - dayOffset * 1440;
        var baseDate = DateFromDayKey(dayKey, tz);
        if (baseDate is null) return null;
        var local = TimeZoneInfo.ConvertTimeFromUtc(
            DateTime.SpecifyKind(baseDate.Value, DateTimeKind.Utc), tz);
        var shifted = local.AddDays(dayOffset);
        var wallClock = new DateTime(shifted.Year, shifted.Month, shifted.Day,
                                     minuteOfDay / 60, minuteOfDay % 60, 0, DateTimeKind.Unspecified);
        try
        {
            return TimeZoneInfo.ConvertTimeToUtc(wallClock, tz);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>任务未来 N 天内活跃的 dayKey 列表（含起始日；once 只返回其指定日）。</summary>
    public static List<string> UpcomingDays(TaskItem task, string fromKey, int count, TimeZoneInfo tz) =>
        EnumerateDays(fromKey, count, tz)
            .Where(day => task.RepeatRule.IsActiveOn(day, WeekdayOfDayKey(day, tz) ?? 1))
            .ToList();

    /// <summary>跨午夜结束标签：不跨天返回 null，跨 1 天返回「次日」。</summary>
    public static string? EndLabel(int startMinutes, int duration)
    {
        var info = EndInfo(startMinutes, duration);
        if (!info.CrossesMidnight) return null;
        return info.SpillDays == 1 ? "次日" : $"+{info.SpillDays}天";
    }
}

/// <summary>统计口径的 C# 移植（与 Sources/KeychainStore.swift 的 StatsCore 对应）。</summary>
public static class StatsCore
{
    /// <summary>“该天活跃”：重复规则命中、截止未过、未被跳过，且不早于创建日。</summary>
    public static bool WasActive(TaskItem task, string dayKey, int weekday) =>
        task.IsActiveOn(dayKey, weekday)
        && (task.CreatedOn.Length == 0 || string.CompareOrdinal(task.CreatedOn, dayKey) <= 0);

    public static (int Total, int Done) DayCounts(IEnumerable<PlanSheet> sheets, string dayKey, int weekday)
    {
        int total = 0, done = 0;
        foreach (var sheet in sheets)
        {
            foreach (var task in sheet.Tasks)
            {
                if (!WasActive(task, dayKey, weekday)) continue;
                total++;
                if (task.DoneDays.Contains(dayKey)) done++;
            }
        }
        return (total, done);
    }
}
