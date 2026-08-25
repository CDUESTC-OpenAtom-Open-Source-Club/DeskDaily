import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - 基础枚举

enum TZMode: Int, Codable, Hashable {
    case system = 0   // 优先读取系统时区
    case beijing = 1  // 固定北京时间
}

enum WindowMode: Int, Codable, Hashable {
    case desktop = 0  // 贴附桌面（实验性：部分环境收不到点击）
    case floating = 1 // 悬浮置顶（默认，兼容性最佳）
}

enum ProgressMode: Int, Codable, Hashable {
    case count = 0    // 圈内显示已完成数量
    case percent = 1  // 圈内显示完成百分比
}

// MARK: - 重复规则

enum RepeatKind: Int, Codable, Hashable {
    case daily = 0
    case once = 1
    case weekly = 2
}

struct RepeatRule: Codable, Equatable {
    var kind: RepeatKind = .daily
    var weekdays: Set<Int> = []  // 1=周日 … 7=周六（Calendar.weekday）
    var date: String = ""        // kind == .once 时生效

    static func once(date: String) -> RepeatRule { RepeatRule(kind: .once, date: date) }
    static func weekly(_ days: Set<Int>) -> RepeatRule { RepeatRule(kind: .weekly, weekdays: days) }

    func isActive(on dayKey: String, weekday: Int) -> Bool {
        switch kind {
        case .daily: return true
        case .once: return date == dayKey
        case .weekly: return weekdays.contains(weekday)
        }
    }
}

// MARK: - 数据模型

struct AppSettings: Codable, Equatable {
    var tzMode: TZMode = .system
    var windowMode: WindowMode = .floating
    var progressMode: ProgressMode = .count
    var soundOn: Bool = true
    var notifOn: Bool = true
    var windowFrame: CGRect? = nil
    // AI 助手（任意 OpenAI 兼容接口）
    var aiBaseURL: String = ""
    var aiModel: String = ""
    var apiKey: String = ""
    var memoryEnabled: Bool = true
    // v1.1 一次性迁移标记：老用户默认切换到悬浮置顶
    var migratedFloating: Bool = false

    init() {}

    // 兼容旧数据文件：缺失的新字段回落到默认值，不丢用户数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tzMode = try c.decodeIfPresent(TZMode.self, forKey: .tzMode) ?? .system
        windowMode = try c.decodeIfPresent(WindowMode.self, forKey: .windowMode) ?? .floating
        progressMode = try c.decodeIfPresent(ProgressMode.self, forKey: .progressMode) ?? .count
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        notifOn = try c.decodeIfPresent(Bool.self, forKey: .notifOn) ?? true
        windowFrame = try c.decodeIfPresent(CGRect.self, forKey: .windowFrame)
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? ""
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? ""
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? true
        migratedFloating = try c.decodeIfPresent(Bool.self, forKey: .migratedFloating) ?? false
    }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var remindAt: Int? = nil          // 开始时间，当天分钟数，如 8*60+30 表示 08:30
    var durationMinutes: Int? = nil   // 时段时长（分钟），有值则结束时再提醒一次
    var repeatRule = RepeatRule()
    var createdOn: String = ""        // 创建日期 dayKey
    var doneDays: Set<String> = []         // 每天的完成状态，跨天自动重置
    var remindedDays: Set<String> = []     // 已提醒过“开始”的日期
    var endRemindedDays: Set<String> = []  // 已提醒过“结束”的日期

    init(id: UUID = UUID(), title: String, remindAt: Int? = nil, durationMinutes: Int? = nil,
         repeatRule: RepeatRule = RepeatRule(), createdOn: String = "",
         doneDays: Set<String> = [], remindedDays: Set<String> = [], endRemindedDays: Set<String> = []) {
        self.id = id
        self.title = title
        self.remindAt = remindAt
        self.durationMinutes = durationMinutes
        self.repeatRule = repeatRule
        self.createdOn = createdOn
        self.doneDays = doneDays
        self.remindedDays = remindedDays
        self.endRemindedDays = endRemindedDays
    }

    private enum LegacyKeys: String, CodingKey { case repeatDaily }

    // 兼容旧版 repeatDaily: Bool → 新 RepeatRule
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        remindAt = try c.decodeIfPresent(Int.self, forKey: .remindAt)
        if let rule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) {
            repeatRule = rule
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let daily = try legacy.decodeIfPresent(Bool.self, forKey: .repeatDaily) ?? true
            let created = try c.decodeIfPresent(String.self, forKey: .createdOn) ?? ""
            repeatRule = daily ? RepeatRule() : RepeatRule.once(date: created)
        }
        createdOn = try c.decodeIfPresent(String.self, forKey: .createdOn) ?? ""
        doneDays = try c.decodeIfPresent(Set<String>.self, forKey: .doneDays) ?? []
        remindedDays = try c.decodeIfPresent(Set<String>.self, forKey: .remindedDays) ?? []
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        endRemindedDays = try c.decodeIfPresent(Set<String>.self, forKey: .endRemindedDays) ?? []
    }
}

struct PlanSheet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String
    var tasks: [TaskItem] = []
}

enum SheetTheme {
    static let palette: [(name: String, hex: String)] = [
        ("紫", "8B5CF6"), ("靛蓝", "6366F1"), ("蓝", "3B82F6"), ("青", "06B6D4"),
        ("绿", "10B981"), ("薄荷", "14B8A6"), ("琥珀", "F59E0B"), ("橙红", "F97316"),
        ("粉", "EC4899"), ("石墨", "64748B")
    ]
}

struct MemoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var content: String
    var createdAt: Date = Date()
}

struct AppData: Codable {
    var settings = AppSettings()
    var sheets: [PlanSheet] = []
    var activeSheetId: UUID?
    var lastSeenDay: String = ""
    var memories: [MemoryEntry] = []
    var chatHistory: [ChatMessage] = []

    init() {}

    init(settings: AppSettings, sheets: [PlanSheet], activeSheetId: UUID?,
         lastSeenDay: String, memories: [MemoryEntry], chatHistory: [ChatMessage]) {
        self.settings = settings
        self.sheets = sheets
        self.activeSheetId = activeSheetId
        self.lastSeenDay = lastSeenDay
        self.memories = memories
        self.chatHistory = chatHistory
    }

    private enum LegacyKeys: String, CodingKey { case tasks }

    // 兼容旧版顶层 tasks 数组 → 迁移为单个「今日计划」表
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        if let list = try c.decodeIfPresent([PlanSheet].self, forKey: .sheets) {
            sheets = list
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let oldTasks = try legacy.decodeIfPresent([TaskItem].self, forKey: .tasks), !oldTasks.isEmpty {
                sheets = [PlanSheet(name: "今日计划", colorHex: "8B5CF6", tasks: oldTasks)]
            }
        }
        activeSheetId = try c.decodeIfPresent(UUID.self, forKey: .activeSheetId)
        lastSeenDay = try c.decodeIfPresent(String.self, forKey: .lastSeenDay) ?? ""
        memories = try c.decodeIfPresent([MemoryEntry].self, forKey: .memories) ?? []
        chatHistory = try c.decodeIfPresent([ChatMessage].self, forKey: .chatHistory) ?? []
    }
}

// MARK: - 声音与通知

enum Sound {
    static func play() {
        if let s = NSSound(named: "Glass") {
            s.play()
        } else if let s = NSSound(named: "Ping") {
            s.play()
        } else {
            NSSound.beep()
        }
    }
}

enum Notify {
    static var center: UNUserNotificationCenter? {
        // 直接运行裸二进制（无 bundle）时不可用，避免崩溃
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func requestAuth() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings: AppSettings { didSet { if settings != oldValue { persist() } } }
    @Published var sheets: [PlanSheet] { didSet { persist() } }
    @Published var activeSheetId: UUID? { didSet { persist() } }
    @Published var memories: [MemoryEntry] { didSet { persist() } }
    @Published var chatHistory: [ChatMessage] { didSet { persist() } }
    @Published var currentDay: String
    @Published var nowMinutes: Int
    @Published var tick: Int = 0

    private var timerCancellable: AnyCancellable?

    // 测试用：把“现在”向前平移 N 分钟
    static var timeShift: TimeInterval = {
        if let raw = ProcessInfo.processInfo.environment["DD_TIME_SHIFT_MINUTES"], let minutes = Double(raw) {
            return minutes * 60
        }
        return 0
    }()

    var tz: TimeZone {
        settings.tzMode == .system ? TimeZone.autoupdatingCurrent : TimeZone(identifier: "Asia/Shanghai")!
    }

    init() {
        let loaded = Store.load()
        var loadedSettings = loaded.settings
        if !loadedSettings.migratedFloating {
            // v1.1：贴附桌面在部分环境收不到点击，老用户一次性迁到悬浮置顶
            loadedSettings.windowMode = .floating
            loadedSettings.migratedFloating = true
        }
        settings = loadedSettings
        var resolvedSheets = loaded.sheets
        if resolvedSheets.isEmpty {
            let seed = loaded.lastSeenDay.isEmpty ? Store.seedTasks() : []
            resolvedSheets = [PlanSheet(name: "今日计划", colorHex: "8B5CF6", tasks: seed)]
        }
        sheets = resolvedSheets
        activeSheetId = loaded.activeSheetId ?? resolvedSheets.first?.id
        memories = loaded.memories
        chatHistory = loaded.chatHistory
        currentDay = ""
        nowMinutes = 0
        refreshNow()
        persist()
        timerCancellable = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.onTimer() }
    }

    // MARK: 当前计划表

    var activeIndex: Int? { sheets.firstIndex { $0.id == activeSheetId } }

    var activeSheet: PlanSheet? {
        guard let i = activeIndex else { return sheets.first }
        return sheets[i]
    }

    var activeSheetName: String { activeSheet?.name ?? "计划表" }
    var activeSheetColorHex: String { activeSheet?.colorHex ?? "8B5CF6" }

    private func mutateActiveTasks(_ body: (inout [TaskItem]) -> Void) {
        guard let i = activeIndex else { return }
        body(&sheets[i].tasks)
    }

    func addSheet(name: String, colorHex: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sheet = PlanSheet(name: clean.isEmpty ? "计划表 \(sheets.count + 1)" : String(clean.prefix(12)),
                              colorHex: colorHex, tasks: [])
        sheets.append(sheet)
        activeSheetId = sheet.id
    }

    func updateSheet(_ id: UUID, name: String, colorHex: String) {
        guard let i = sheets.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { sheets[i].name = String(clean.prefix(12)) }
        sheets[i].colorHex = colorHex
    }

    func deleteActiveSheet() {
        guard sheets.count > 1, let i = activeIndex else { return }
        let removed = sheets.remove(at: i)
        if activeSheetId == removed.id { activeSheetId = sheets.first?.id }
    }

    // MARK: 时间

    static func now() -> Date { Date().addingTimeInterval(timeShift) }

    static func dayKey(tz: TimeZone, date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func dayKey(_ date: Date = Store.now()) -> String { Store.dayKey(tz: tz, date: date) }

    func minutesNow() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: Store.now())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func weekdayNow() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.weekday], from: Store.now()).weekday ?? 1
    }

    func refreshNow() {
        nowMinutes = minutesNow()
        tick &+= 1
        let d = dayKey()
        if d != currentDay {
            currentDay = d
        }
        checkReminders()
    }

    private func onTimer() {
        nowMinutes = minutesNow()
        tick &+= 1
        let d = dayKey()
        if d != currentDay {
            currentDay = d
            if settings.notifOn {
                Notify.post(title: "🌅 新的一天", body: "「\(activeSheetName)」清单已刷新，今天共有 \(visibleTasks.count) 项任务")
            }
            persist()
        }
        checkReminders()
    }

    // MARK: 展示

    var visibleTasks: [TaskItem] {
        guard let i = activeIndex else { return [] }
        let weekday = weekdayNow()
        return sheets[i].tasks
            .filter { $0.repeatRule.isActive(on: currentDay, weekday: weekday) }
            .sorted { a, b in
                let am = a.remindAt ?? Int.max
                let bm = b.remindAt ?? Int.max
                if am != bm { return am < bm }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    var doneCount: Int { visibleTasks.filter { isDone($0) }.count }

    func isDone(_ task: TaskItem) -> Bool { task.doneDays.contains(currentDay) }

    func dateHeader() -> (weekday: String, date: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = tz
        f.dateFormat = "EEEE"
        let weekday = f.string(from: Store.now())
        f.dateFormat = "M月d日"
        let date = f.string(from: Store.now())
        return (weekday, date)
    }

    func clockString() -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f.string(from: Store.now())
    }

    func tzShortLabel() -> String {
        settings.tzMode == .beijing ? "北京时间" : "系统时区"
    }

    func tzLabel() -> String {
        switch settings.tzMode {
        case .beijing:
            return "北京时间 UTC+8"
        case .system:
            let t = tz
            let secs = t.secondsFromGMT(for: Store.now())
            let sign = secs >= 0 ? "+" : "-"
            let h = abs(secs) / 3600
            let m = (abs(secs) % 3600) / 60
            let name = t.identifier.replacingOccurrences(of: "_", with: " ")
            let mm = m == 0 ? "" : String(format: ":%02d", m)
            return "系统时区 \(name) UTC\(sign)\(h)\(mm)"
        }
    }

    func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    func dateFromMinutes(_ minutes: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        return cal.date(from: c) ?? Store.now()
    }

    func minutesFromDate(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: 编辑

    func addTask(title: String, rule: RepeatRule, remindAt: Int? = nil, duration: Int? = nil) {
        let t = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !t.isEmpty else { return }
        let durationValue = (duration ?? 0) > 0 ? duration : nil
        mutateActiveTasks { list in
            list.append(TaskItem(title: t, remindAt: remindAt, durationMinutes: durationValue,
                                 repeatRule: rule, createdOn: currentDay))
        }
    }

    func delete(_ id: UUID) {
        mutateActiveTasks { list in
            list.removeAll { $0.id == id }
        }
    }

    func rename(_ id: UUID, to title: String) {
        let t = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !t.isEmpty else { return }
        mutateActiveTasks { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].title = t
        }
    }

    func setRemind(_ id: UUID, minutes: Int?, duration: Int? = nil) {
        mutateActiveTasks { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].remindAt = minutes
            list[i].durationMinutes = (duration ?? 0) > 0 ? duration : nil
            if minutes == nil || minutes! > nowMinutes {
                list[i].remindedDays.remove(currentDay)
            }
            if minutes == nil || minutes! + (list[i].durationMinutes ?? 0) > nowMinutes {
                list[i].endRemindedDays.remove(currentDay)
            }
        }
    }

    func setRule(_ id: UUID, rule: RepeatRule) {
        mutateActiveTasks { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].repeatRule = rule
        }
    }

    func toggleDone(_ id: UUID) {
        mutateActiveTasks { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            if list[i].doneDays.contains(currentDay) {
                list[i].doneDays.remove(currentDay)
            } else {
                list[i].doneDays.insert(currentDay)
            }
        }
    }

    func resetToday() {
        mutateActiveTasks { list in
            for i in list.indices {
                list[i].doneDays.remove(currentDay)
                list[i].remindedDays.remove(currentDay)
            }
        }
    }

    func clearAll() {
        mutateActiveTasks { list in
            list.removeAll()
        }
    }

    /// 用 AI 生成的清单整体覆盖当前计划表
    func replaceAll(with newTasks: [(title: String, repeatDaily: Bool, remindAt: Int?, duration: Int?)]) {
        var items: [TaskItem] = []
        for task in newTasks {
            let clean = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !clean.isEmpty else { continue }
            let rule = task.repeatDaily ? RepeatRule() : RepeatRule.once(date: currentDay)
            let durationValue = (task.duration ?? 0) > 0 ? task.duration : nil
            items.append(TaskItem(title: clean, remindAt: task.remindAt, durationMinutes: durationValue,
                                  repeatRule: rule, createdOn: currentDay))
        }
        guard !items.isEmpty else { return }
        mutateActiveTasks { list in
            list = items
        }
    }

    // MARK: 提醒

    private func checkReminders() {
        guard let i = activeIndex else { return }
        let weekday = weekdayNow()
        for j in sheets[i].tasks.indices {
            let task = sheets[i].tasks[j]
            guard task.repeatRule.isActive(on: currentDay, weekday: weekday),
                  let start = task.remindAt,
                  !task.doneDays.contains(currentDay) else { continue }
            // 时段开始提醒（“阅读前”那一次）
            if nowMinutes >= start, !task.remindedDays.contains(currentDay) {
                sheets[i].tasks[j].remindedDays.insert(currentDay)
                // 只在时间点后 30 分钟内提醒，避免打开 App 时补发一堆过期提醒
                if nowMinutes - start <= 30 {
                    fireReminder(for: task, phase: .start)
                }
            }
            // 时段结束提醒（“阅读后”那一次，有设定时长才有）
            if let duration = task.durationMinutes {
                let end = start + duration
                if nowMinutes >= end, !task.endRemindedDays.contains(currentDay) {
                    sheets[i].tasks[j].endRemindedDays.insert(currentDay)
                    if nowMinutes - end <= 30 {
                        fireReminder(for: sheets[i].tasks[j], phase: .end)
                    }
                }
            }
        }
    }

    private enum ReminderPhase { case start, end }

    private func fireReminder(for task: TaskItem, phase: ReminderPhase) {
        let start = timeString(task.remindAt ?? 0)
        var title = "⏰ \(task.title)"
        var body = "到设定的提醒时间了（\(start)），别忘了完成它"
        if phase == .start, let d = task.durationMinutes {
            body = "时段 \(start)-\(timeString((task.remindAt ?? 0) + d)) 开始，时长 \(d) 分钟"
        } else if phase == .end {
            title = "✅ 时间到：\(task.title)"
            body = "本时段（\(start)-\(timeString((task.remindAt ?? 0) + (task.durationMinutes ?? 0)))）结束了，完成就打勾 ✓"
        }
        if settings.soundOn { Sound.play() }
        if settings.notifOn {
            Notify.post(title: title, body: body)
        }
    }

    // MARK: 长期记忆

    func addMemory(_ content: String) {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4 else { return }
        let trimmed = String(clean.prefix(120))
        // 去重：完全相同或互相包含的旧记忆不再重复记录
        guard !memories.contains(where: { $0.content == trimmed || $0.content.contains(trimmed) || trimmed.contains($0.content) }) else { return }
        memories.append(MemoryEntry(content: trimmed))
        if memories.count > 60 { memories.removeFirst(memories.count - 60) }
    }

    func deleteMemory(_ id: UUID) { memories.removeAll { $0.id == id } }

    func clearMemories() { memories.removeAll() }

    // MARK: 持久化

    static var dataURL: URL {
        if let dir = ProcessInfo.processInfo.environment["DD_DATA_DIR"] {
            return URL(fileURLWithPath: dir).appendingPathComponent("data.json")
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: "DeskDaily-data.json")
        }
        let appDir = base.appendingPathComponent("DeskDaily", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("data.json")
    }

    static func load() -> AppData {
        guard let data = try? Data(contentsOf: dataURL) else { return AppData() }
        return (try? JSONDecoder().decode(AppData.self, from: data)) ?? AppData()
    }

    func persist() {
        let data = AppData(settings: settings, sheets: sheets, activeSheetId: activeSheetId,
                           lastSeenDay: currentDay, memories: memories, chatHistory: chatHistory)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: Store.dataURL, options: .atomic)
        }
    }

    static func seedTasks() -> [TaskItem] {
        [
            TaskItem(title: "喝一杯温水，简单拉伸", remindAt: 8 * 60 + 30),
            TaskItem(title: "列出今天最重要的 3 件事", remindAt: 9 * 60),
            TaskItem(title: "专注完成一个核心任务", durationMinutes: 90),
            TaskItem(title: "运动半小时", remindAt: 18 * 60 + 30, durationMinutes: 30),
            TaskItem(title: "睡前阅读 20 分钟", remindAt: 22 * 60, durationMinutes: 20)
        ]
    }
}
