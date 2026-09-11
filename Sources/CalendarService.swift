import Foundation
import Combine
import EventKit

// MARK: - 今日日历只读集成（v2.5 日历版）
// 隐私边界：绝不写入日历；事件数据只保存在内存，不写入 data.json；
// 仅当用户在设置里打开「读取今日日历」后才发起授权与读取。

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    /// 今天的日历事件（按 start 升序；内存态）
    @Published var events: [CalendarEvent] = []
    /// 系统拒绝了日历访问（卡片与设置页据此提示去「系统设置 → 隐私」开启）
    @Published var authorizationDenied = false

    /// EKEventStore 实例保持复用（反复创建会拖慢读取）
    private let eventStore = EKEventStore()
    /// 防抖：授权/读取进行中不重复触发
    private var refreshing = false

    // MARK: 刷新入口

    /// 仅 calendarEnabled 时请求授权并读取今天的事件。
    /// 刷新时机：App 启动后、设置开关打开时、跨天刷新时（Store.onTimer）。
    func refreshIfNeeded(settings: AppSettings) {
        guard settings.calendarEnabled, !refreshing else { return }
        refreshing = true
        requestEventAccess { [weak self] granted in
            guard let self else { return }
            self.refreshing = false
            self.authorizationDenied = !granted
            guard granted else {
                self.clearEvents()
                return
            }
            self.loadTodayEvents()
        }
    }

    /// 关闭开关或清空内存中的事件缓存（不动日历本体）
    func clearEvents() {
        events = []
    }

    // MARK: 授权（macOS 13 / 14+ 双路径，零 deprecation 警告）

    private func requestEventAccess(_ completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            // 旧 API requestAccess(to:) 在 macOS 14 起 deprecated，但 macOS 13 必须用它；
            // 编译目标为 macos13.0 时直接调用会产生弃用警告，改经 ObjC Selector 调用保持零警告。
            // Selector 对应 -requestAccessToEntityType:completion:，block 签名与
            // EKEventStoreRequestAccessCompletionHandler（Bool, Error?）一致。
            let selector = NSSelectorFromString("requestAccessToEntityType:completion:")
            guard eventStore.responds(to: selector) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let handler: @convention(block) (Bool, Error?) -> Void = { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
            _ = eventStore.perform(selector, with: EKEntityType.event, with: handler)
        }
    }

    // MARK: 读取今天的事件

    private func loadTodayEvents() {
        let tz = Store.shared.tz
        let dayKey = Store.shared.currentDay
        guard let bounds = CalendarService.dayBounds(forDayKey: dayKey, tz: tz) else { return }
        let predicate = eventStore.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: nil)
        let found = eventStore.events(matching: predicate)
        // 与当天有交集的事件全部保留（含跨天事件），按开始时间排序后映射为纯值类型
        let mapped = found
            .map { event -> CalendarEvent in
                let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rawID = event.eventIdentifier ?? ""
                let id = rawID.isEmpty ? UUID().uuidString : rawID
                return CalendarEvent(id: id,
                                     title: title.isEmpty ? "（无标题）" : title,
                                     start: event.startDate,
                                     end: event.endDate,
                                     isAllDay: event.isAllDay)
            }
            .sorted { $0.start < $1.start }
        self.events = mapped
    }

    // MARK: 纯函数（不依赖 EKEventStore，可独立测试）

    /// "yyyy-MM-dd" → 当天 [0 点, 24 点) 边界（24 点 = 次日 0 点那一瞬间）；解析失败返回 nil
    static func dayBounds(forDayKey key: String, tz: TimeZone) -> (start: Date, end: Date)? {
        guard let noon = OccurrenceKit.date(fromDayKey: key, tz: tz) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.startOfDay(for: noon)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }

    /// 任务候选时段与日历事件的重叠检测：
    /// - 无时长的候选按占用 30 分钟计；
    /// - 跨午夜候选的溢出部分忽略，只比对起始日当天（候选区间夹到 [0, 1440)）；
    /// - 跨午夜 / 跨天事件同样夹进当天窗口参与比对（昨天 23:00 开始的事件按今天 0 点起占用）；
    /// - 返回首个命中的事件（入参已按 start 排序，即最早命中的那个）。
    static func overlappingEvent(startMinutes: Int, duration: Int?, dayKey: String, tz: TimeZone,
                                 events: [CalendarEvent]) -> CalendarEvent? {
        guard let bounds = dayBounds(forDayKey: dayKey, tz: tz) else { return nil }
        let dur = (duration ?? 0) > 0 ? duration! : 30
        let candidateStart = max(startMinutes, 0)
        let candidateEnd = min(startMinutes + dur, 1440)
        guard candidateStart < candidateEnd else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        func minutesOfDay(_ date: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        for event in events {
            if event.isAllDay {
                // 全天事件占用整天 [0, 1440)，与当天任意有效候选都重叠
                return event
            }
            // 与当天窗口完全无交集的事件（前一天已结束 / 次日才开始）不参与比对
            guard event.start < bounds.end, event.end > bounds.start else { continue }
            let s = event.start <= bounds.start ? 0 : minutesOfDay(event.start)
            let e = event.end >= bounds.end ? 1440 : minutesOfDay(event.end)
            if candidateStart < e && s < candidateEnd { return event }
        }
        return nil
    }

    /// AI 忙闲上下文：每行一条「HH:mm-HH:mm 标题」，全天事件标「全天」，无事件返回空串
    static func aiBusyText(events: [CalendarEvent], tz: TimeZone) -> String {
        events.map { event -> String in
            if event.isAllDay {
                return "全天 \(event.title)"
            }
            return "\(timeRangeText(for: event, tz: tz)) \(event.title)"
        }.joined(separator: "\n")
    }

    /// 事件时间文案：全天 →「全天」，否则「HH:mm-HH:mm」（显示与 AI 文案共用）
    static func timeRangeText(for event: CalendarEvent, tz: TimeZone) -> String {
        guard !event.isAllDay else { return "全天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: event.start))-\(formatter.string(from: event.end))"
    }
}
