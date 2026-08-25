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

// MARK: - 时段（头部问候语 / 空状态图标按时段切换）

enum DayPeriod {
    case morning, noon, afternoon, evening, lateNight

    /// 5-11 早上好 / 11-13 中午好 / 13-18 下午好 / 18-23 晚上好 / 23-5 夜深了
    var greeting: String {
        switch self {
        case .morning: return "早上好"
        case .noon: return "中午好"
        case .afternoon: return "下午好"
        case .evening: return "晚上好"
        case .lateNight: return "夜深了"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .noon: return "sun.max"
        case .afternoon: return "cloud.sun"
        case .evening: return "sunset"
        case .lateNight: return "moon.stars"
        }
    }
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
    // AI 睡前复盘提醒时间（当天分钟数，如 22*60 表示 22:00；nil = 关闭）
    var reviewTime: Int? = nil
    // 全局热键 ⌥⇧D 显示/隐藏卡片（默认开）
    var globalHotkey: Bool = true
    // 菜单栏迷你入口（默认关，避免打扰）
    var statusBarIcon: Bool = false

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
        reviewTime = try c.decodeIfPresent(Int.self, forKey: .reviewTime)
        globalHotkey = try c.decodeIfPresent(Bool.self, forKey: .globalHotkey) ?? true
        statusBarIcon = try c.decodeIfPresent(Bool.self, forKey: .statusBarIcon) ?? false
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
    // 计划表模板库（批次③）
    var templates: [PlanSheet] = []

    init() {}

    init(settings: AppSettings, sheets: [PlanSheet], activeSheetId: UUID?,
         lastSeenDay: String, memories: [MemoryEntry], chatHistory: [ChatMessage],
         templates: [PlanSheet] = []) {
        self.settings = settings
        self.sheets = sheets
        self.activeSheetId = activeSheetId
        self.lastSeenDay = lastSeenDay
        self.memories = memories
        self.chatHistory = chatHistory
        self.templates = templates
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
        templates = try c.decodeIfPresent([PlanSheet].self, forKey: .templates) ?? []
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

    // 任务提醒通知分类：带「完成 / 推迟10分钟」操作按钮
    static let taskReminderCategory = "TASK_REMINDER"
    static let actionComplete = "COMPLETE"
    static let actionPostpone10 = "POSTPONE10"
    // 睡前复盘通知分类：带「开始复盘」按钮
    static let reviewCategory = "REVIEW_REMINDER"
    static let actionStartReview = "START_REVIEW"
    // 番茄钟专注结束通知分类：带「标记完成」按钮
    static let focusEndCategory = "FOCUS_END"

    /// 启动时注册分类（重复注册安全，系统以最后一次为准）
    static func registerCategories() {
        guard let center = center else { return }
        let complete = UNNotificationAction(identifier: actionComplete, title: "完成", options: [])
        let postpone = UNNotificationAction(identifier: actionPostpone10, title: "推迟10分钟", options: [])
        let taskCategory = UNNotificationCategory(identifier: taskReminderCategory,
                                                  actions: [complete, postpone],
                                                  intentIdentifiers: [],
                                                  options: [])
        let startReview = UNNotificationAction(identifier: actionStartReview, title: "开始复盘", options: [])
        let reviewCat = UNNotificationCategory(identifier: reviewCategory,
                                               actions: [startReview],
                                               intentIdentifiers: [],
                                               options: [])
        let focusComplete = UNNotificationAction(identifier: actionComplete, title: "标记完成", options: [])
        let focusCat = UNNotificationCategory(identifier: focusEndCategory,
                                              actions: [focusComplete],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([taskCategory, reviewCat, focusCat])
    }

    /// taskID/sheetID 齐备时挂上任务分类（可从通知直接完成/推迟）；「新的一天」等普通通知不带按钮
    static func post(title: String, body: String, taskID: String? = nil, sheetID: String? = nil) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let t = taskID, let s = sheetID {
            content.categoryIdentifier = taskReminderCategory
            content.userInfo = ["taskID": t, "sheetID": s]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    /// 睡前复盘提醒：点击通知或「开始复盘」按钮都会打开 AI 复盘对话（userInfo 标记 open_review）
    static func postReview() {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = "🌙 该复盘了"
        content.body = "今天过得怎么样？点「开始复盘」，让 AI 陪你回顾今天的完成情况"
        content.sound = .default
        content.categoryIdentifier = reviewCategory
        content.userInfo = ["open_review": true]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    /// 番茄钟专注结束：带「标记完成」动作（复用 taskID 路由到 completeTask）
    static func postFocusEnd(taskTitle: String, taskID: UUID, sheetID: UUID) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = "🍅 专注完成"
        content.body = "「\(taskTitle)」的专注时段结束了，完成就打勾 ✓"
        content.sound = .default
        content.categoryIdentifier = focusEndCategory
        content.userInfo = ["taskID": taskID.uuidString, "sheetID": sheetID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

// MARK: - Store

/// 最近一次删除的任务暂存（撤销删除用，不持久化）
struct DeletedTaskInfo: Equatable {
    let task: TaskItem
    let index: Int
}

/// 番茄钟专注会话（内存态，不持久化；同一时间只有一个）
struct FocusSession: Equatable {
    var taskID: UUID
    var endsAt: Date
    var totalSeconds: Int
    /// 暂停时的剩余秒数（nil = 运行中）
    var pausedRemaining: Int? = nil
    var isPaused: Bool { pausedRemaining != nil }
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings: AppSettings { didSet { if settings != oldValue { persist() } } }
    @Published var sheets: [PlanSheet] { didSet { persist() } }
    @Published var activeSheetId: UUID? { didSet { persist() } }
    @Published var memories: [MemoryEntry] { didSet { persist() } }
    @Published var chatHistory: [ChatMessage] { didSet { persist() } }
    @Published var templates: [PlanSheet] { didSet { persist() } }
    @Published var currentDay: String
    @Published var nowMinutes: Int
    @Published var tick: Int = 0
    /// 撤销删除暂存（只保留最近一次，不写入 data.json）
    @Published var lastDeleted: DeletedTaskInfo? = nil
    /// 番茄钟专注会话（内存态，不写入 data.json）
    @Published var focusSession: FocusSession? = nil

    private var timerCancellable: AnyCancellable?
    /// 睡前复盘当天已发过的标记（内存态，不持久化；跨天自动失效）
    private var reviewFiredDay: String = ""

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
        templates = loaded.templates
        currentDay = ""
        nowMinutes = 0
        refreshNow()
        persist()
        writeStartupBackup()
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

    // MARK: 模板库

    /// 当前表存为模板：深拷贝、清掉勾选/提醒状态，名字带日期后缀防重名
    func saveCurrentAsTemplate() {
        guard let sheet = activeSheet else { return }
        var copy = sheet
        copy.id = UUID()
        copy.name = String("\(sheet.name) \(shortDayLabel(currentDay))".prefix(16))
        for i in copy.tasks.indices {
            copy.tasks[i].id = UUID()
            copy.tasks[i].doneDays = []
            copy.tasks[i].remindedDays = []
            copy.tasks[i].endRemindedDays = []
            copy.tasks[i].createdOn = ""
            // 模板与具体日期无关：仅今天 → 每天
            if copy.tasks[i].repeatRule.kind == .once {
                copy.tasks[i].repeatRule = RepeatRule()
            }
        }
        templates.append(copy)
    }

    /// 从模板深拷贝新建一张表并切换过去
    func instantiateTemplate(_ id: UUID) {
        guard let tpl = templates.first(where: { $0.id == id }) else { return }
        var copy = tpl
        copy.id = UUID()
        copy.name = stripTemplateDateStamp(tpl.name)
        for i in copy.tasks.indices {
            copy.tasks[i].id = UUID()
            copy.tasks[i].doneDays = []
            copy.tasks[i].remindedDays = []
            copy.tasks[i].endRemindedDays = []
            copy.tasks[i].createdOn = currentDay
        }
        sheets.append(copy)
        activeSheetId = copy.id
    }

    func deleteTemplate(_ id: UUID) {
        templates.removeAll { $0.id == id }
    }

    /// 去掉模板名末尾的 " M/d" 日期戳
    private func stripTemplateDateStamp(_ name: String) -> String {
        if let regex = try? NSRegularExpression(pattern: #"\s+\d{1,2}/\d{1,2}$"#),
           let m = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            return (name as NSString).replacingCharacters(in: m.range, with: "")
        }
        return name
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
        checkReviewReminder()
        checkFocusEnd()
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
        checkReviewReminder()
        checkFocusEnd()
    }

    // MARK: 展示

    /// 明天的 dayKey（周视图用）
    func tomorrowKey() -> String? { dayKey(byAddingDays: 1, toKey: currentDay) }

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

    /// 周视图：offset == 1 查看明天（重复规则活跃于明天，或 once.date = 明天）
    func visibleTasks(offset: Int) -> [TaskItem] {
        guard offset == 1 else { return visibleTasks }
        guard let i = activeIndex, let key = tomorrowKey() else { return [] }
        let weekday = weekday(ofDayKey: key)
        return sheets[i].tasks
            .filter { $0.repeatRule.isActive(on: key, weekday: weekday) }
            .sorted { a, b in
                let am = a.remindAt ?? Int.max
                let bm = b.remindAt ?? Int.max
                if am != bm { return am < bm }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    var doneCount: Int { visibleTasks.filter { isDone($0) }.count }

    func isDone(_ task: TaskItem) -> Bool { task.doneDays.contains(currentDay) }

    /// 周视图：明天视角用明天的 key 判断完成态（还没到，天然都是未完成）
    func isDone(_ task: TaskItem, offset: Int) -> Bool {
        guard offset == 1, let key = tomorrowKey() else { return task.doneDays.contains(currentDay) }
        return task.doneDays.contains(key)
    }

    func dateHeader(offset: Int = 0) -> (weekday: String, date: String) {
        let target: Date
        if offset == 1, let key = tomorrowKey(), let d = date(fromDayKey: key) {
            target = d
        } else {
            target = Store.now()
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = tz
        f.dateFormat = "EEEE"
        let weekday = f.string(from: target)
        f.dateFormat = "M月d日"
        let date = f.string(from: target)
        return (weekday, date)
    }

    func clockString() -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f.string(from: Store.now())
    }

    /// 时段问候（5-11 早上好 / 11-13 中午好 / 13-18 下午好 / 18-23 晚上好 / 23-5 夜深了）
    func dayPeriod() -> DayPeriod {
        switch nowMinutes {
        case 300..<660: return .morning
        case 660..<780: return .noon
        case 780..<1080: return .afternoon
        case 1080..<1380: return .evening
        default: return .lateNight
        }
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
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            lastDeleted = DeletedTaskInfo(task: list[i], index: i)
            list.remove(at: i)
        }
    }

    /// 撤销最近一次删除（恢复到原位置）
    func undoDelete() {
        guard let info = lastDeleted else { return }
        lastDeleted = nil
        mutateActiveTasks { list in
            list.insert(info.task, at: min(info.index, list.count))
        }
    }

    /// 无论当前是否已勾选，都把该任务在今天置为完成（通知按钮「完成」用）
    func completeTask(id: UUID) {
        for i in sheets.indices {
            guard let j = sheets[i].tasks.firstIndex(where: { $0.id == id }) else { continue }
            if !sheets[i].tasks[j].doneDays.contains(currentDay) {
                sheets[i].tasks[j].doneDays.insert(currentDay)
            }
            // 该任务正在专注中 → 一并结束专注
            if focusSession?.taskID == id { focusSession = nil }
            return
        }
    }

    /// 推迟提醒 minutes 分钟；原本无时间则设为当前时间 + minutes（通知按钮「推迟10分钟」用）
    func postponeTask(id: UUID, by minutes: Int) {
        for i in sheets.indices {
            guard let j = sheets[i].tasks.firstIndex(where: { $0.id == id }) else { continue }
            let base = sheets[i].tasks[j].remindAt ?? nowMinutes
            sheets[i].tasks[j].remindAt = min(max(base + minutes, 0), 1439)
            // 清掉当日“已提醒”标记，到新时间点会重新提醒
            sheets[i].tasks[j].remindedDays.remove(currentDay)
            sheets[i].tasks[j].endRemindedDays.remove(currentDay)
            return
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

    // MARK: 番茄钟专注

    func taskByID(_ id: UUID) -> TaskItem? {
        for sheet in sheets {
            if let t = sheet.tasks.first(where: { $0.id == id }) { return t }
        }
        return nil
    }

    /// 专注时长：任务的 durationMinutes（若有且 ≤ 60），否则 25 分钟
    func focusMinutes(for task: TaskItem) -> Int {
        if let d = task.durationMinutes, d > 0, d <= 60 { return d }
        return 25
    }

    /// 开始专注（同一时间只保留一个会话）
    func startFocus(_ id: UUID) {
        guard let task = taskByID(id) else { return }
        let minutes = focusMinutes(for: task)
        focusSession = FocusSession(taskID: id,
                                    endsAt: Store.now().addingTimeInterval(TimeInterval(minutes) * 60),
                                    totalSeconds: minutes * 60,
                                    pausedRemaining: nil)
    }

    func togglePauseFocus() {
        guard var f = focusSession else { return }
        if let remaining = f.pausedRemaining {
            f.endsAt = Store.now().addingTimeInterval(TimeInterval(remaining))
            f.pausedRemaining = nil
        } else {
            f.pausedRemaining = max(Int(f.endsAt.timeIntervalSince(Store.now())), 0)
        }
        focusSession = f
    }

    /// 结束专注并把任务标记为今天完成
    func completeFocus() {
        guard let f = focusSession else { return }
        let id = f.taskID
        focusSession = nil
        completeTask(id: id)
    }

    func stopFocus() { focusSession = nil }

    /// 到点收尾：通知（带「标记完成」）+ 音效（15 秒 tick 里检查）
    private func checkFocusEnd() {
        guard let f = focusSession, f.pausedRemaining == nil, Store.now() >= f.endsAt else { return }
        let task = taskByID(f.taskID)
        focusSession = nil
        if settings.soundOn { Sound.play() }
        if settings.notifOn, let task = task, let sheetID = activeSheet?.id {
            Notify.postFocusEnd(taskTitle: task.title, taskID: task.id, sheetID: sheetID)
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
                    fireReminder(for: task, phase: .start, sheetID: sheets[i].id)
                }
            }
            // 时段结束提醒（“阅读后”那一次，有设定时长才有）
            if let duration = task.durationMinutes {
                let end = start + duration
                if nowMinutes >= end, !task.endRemindedDays.contains(currentDay) {
                    sheets[i].tasks[j].endRemindedDays.insert(currentDay)
                    if nowMinutes - end <= 30 {
                        fireReminder(for: sheets[i].tasks[j], phase: .end, sheetID: sheets[i].id)
                    }
                }
            }
        }
    }

    private enum ReminderPhase { case start, end }

    private func fireReminder(for task: TaskItem, phase: ReminderPhase, sheetID: UUID?) {
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
            Notify.post(title: title, body: body,
                        taskID: task.id.uuidString, sheetID: sheetID?.uuidString)
        }
    }

    // MARK: 睡前复盘提醒

    /// AI 睡前复盘：到点发通知（每天最多一次；15 秒 tick 里检查）
    private func checkReviewReminder() {
        guard settings.notifOn, let reviewAt = settings.reviewTime,
              reviewFiredDay != currentDay, nowMinutes >= reviewAt else { return }
        reviewFiredDay = currentDay
        if settings.soundOn { Sound.play() }
        Notify.postReview()
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
        if let encoded = encodedSnapshot() {
            try? encoded.write(to: Store.dataURL, options: .atomic)
        }
    }

    // MARK: 备份 / 恢复

    /// 当前全部数据的 JSON 快照（导出 / 自动备份共用）
    func encodedSnapshot() -> Data? {
        let data = AppData(settings: settings, sheets: sheets, activeSheetId: activeSheetId,
                           lastSeenDay: currentDay, memories: memories, chatHistory: chatHistory,
                           templates: templates)
        return try? JSONEncoder().encode(data)
    }

    static var backupDir: URL {
        dataURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// 用导入的备份整体替换当前状态（UI 全量刷新）
    func restoreAll(from data: AppData) {
        let oldWindowMode = settings.windowMode
        settings = data.settings
        var restored = data.sheets
        if restored.isEmpty {
            restored = [PlanSheet(name: "今日计划", colorHex: "8B5CF6", tasks: [])]
        }
        sheets = restored
        if let id = data.activeSheetId, restored.contains(where: { $0.id == id }) {
            activeSheetId = id
        } else {
            activeSheetId = restored.first?.id
        }
        memories = data.memories
        chatHistory = data.chatHistory
        templates = data.templates
        if settings.windowMode != oldWindowMode {
            NotificationCenter.default.post(name: .deskDailyWindowModeChanged, object: nil)
        }
        refreshNow()
        persist()
    }

    /// 启动时自动备份当天数据，仅保留最近 7 份
    private func writeStartupBackup() {
        let fm = FileManager.default
        let dir = Store.backupDir
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return
        }
        guard let data = encodedSnapshot() else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz
        formatter.dateFormat = "yyyyMMdd"
        let url = dir.appendingPathComponent("data-\(formatter.string(from: Store.now())).json")
        try? data.write(to: url, options: .atomic)
        // 文件名即日期，倒序排列后删多余的
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let stale = files
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(7)
        for old in stale {
            try? fm.removeItem(at: old)
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
