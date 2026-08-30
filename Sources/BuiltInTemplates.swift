import Foundation

// MARK: - 内置日程模板（不写入用户 templates JSON）

enum TemplateAudience: String, CaseIterable, Hashable {
    case student = "学生"
    case worker = "工作者"
}

struct TemplateVariables: Equatable {
    var startMinutes: Int = 9 * 60
    var commuteMinutes: Int = 40
    var sleepMinutes: Int = 22 * 60 + 30

    static func defaults(for audience: TemplateAudience) -> TemplateVariables {
        switch audience {
        case .student:
            return TemplateVariables(startMinutes: 9 * 60, commuteMinutes: 40, sleepMinutes: 22 * 60 + 30)
        case .worker:
            return TemplateVariables(startMinutes: 9 * 60, commuteMinutes: 45, sleepMinutes: 22 * 60 + 30)
        }
    }
}

struct TemplateTask: Identifiable {
    enum Anchor: Hashable {
        case absolute(Int)
        case start(Int)
        case sleep(Int)
    }

    let id: String
    let title: String
    let anchor: Anchor
    let duration: Int?
    let rule: RepeatRule
    let starred: Bool

    func resolve(with variables: TemplateVariables) throws -> TaskItem {
        let minute: Int
        switch anchor {
        case .absolute(let value): minute = value
        case .start(let offset): minute = variables.startMinutes + offset
        case .sleep(let offset): minute = variables.sleepMinutes + offset
        }
        try TaskItem.validate(remindAt: minute, duration: duration)
        return TaskItem(title: title, remindAt: minute, durationMinutes: duration,
                        repeatRule: rule, createdOn: "", starred: starred)
    }
}

struct BuiltInTemplate: Identifiable {
    let id: String
    let audience: TemplateAudience
    let name: String
    let summary: String
    let suggestedSheetName: String
    let colorHex: String
    let tasks: [TemplateTask]

    static let all: [BuiltInTemplate] = [
        BuiltInTemplate(
            id: "student-class-day", audience: .student, name: "上课日",
            summary: "课程、预习、作业、复习与睡眠的工作日节奏", suggestedSheetName: "课程学习", colorHex: "3B82F6",
            tasks: [
                TemplateTask(id: "wake", title: "起床、喝水和简单整理", anchor: .start(-120), duration: 20, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "commute", title: "通勤 / 到教室", anchor: .start(-40), duration: 35, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "preview", title: "课前预习重点", anchor: .start(-30), duration: 25, rule: .weekly([2,3,4,5,6]), starred: true),
                TemplateTask(id: "class", title: "上午课程", anchor: .start(0), duration: 110, rule: .weekly([2,3,4,5,6]), starred: true),
                TemplateTask(id: "notes", title: "整理当天课堂笔记", anchor: .start(8 * 60 + 30), duration: 30, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "homework", title: "作业专注块", anchor: .sleep(-180), duration: 90, rule: .weekly([2,3,4,5,6]), starred: true),
                TemplateTask(id: "read", title: "睡前阅读与准备明天", anchor: .sleep(0), duration: 20, rule: RepeatRule(), starred: false)
            ]),
        BuiltInTemplate(
            id: "student-exam-week", audience: .student, name: "考试周",
            summary: "保留休息和睡眠的三段式复习安排", suggestedSheetName: "考试周", colorHex: "6366F1",
            tasks: [
                TemplateTask(id: "morning", title: "核心科目复习", anchor: .start(0), duration: 100, rule: RepeatRule(), starred: true),
                TemplateTask(id: "break", title: "离开屏幕、补水和休息", anchor: .start(120), duration: 20, rule: RepeatRule(), starred: false),
                TemplateTask(id: "afternoon", title: "错题整理或模拟题", anchor: .start(300), duration: 90, rule: RepeatRule(), starred: true),
                TemplateTask(id: "exercise", title: "散步或轻运动", anchor: .sleep(-210), duration: 30, rule: RepeatRule(), starred: false),
                TemplateTask(id: "review", title: "睡前回顾今日难点", anchor: .sleep(-60), duration: 30, rule: RepeatRule(), starred: false),
                TemplateTask(id: "sleep", title: "准备睡眠", anchor: .sleep(0), duration: 20, rule: RepeatRule(), starred: false)
            ]),
        BuiltInTemplate(
            id: "worker-standard-day", audience: .worker, name: "标准工作日",
            summary: "通勤、沟通、两段深度工作和收尾复盘", suggestedSheetName: "工作日", colorHex: "10B981",
            tasks: [
                TemplateTask(id: "commute", title: "通勤 / 工作准备", anchor: .start(-45), duration: 35, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "mail", title: "查看今日目标与邮件", anchor: .start(0), duration: 25, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "deep1", title: "深度工作块一", anchor: .start(45), duration: 90, rule: .weekly([2,3,4,5,6]), starred: true),
                TemplateTask(id: "lunch", title: "午餐和离开屏幕", anchor: .start(210), duration: 60, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "deep2", title: "深度工作块二", anchor: .start(390), duration: 75, rule: .weekly([2,3,4,5,6]), starred: true),
                TemplateTask(id: "wrap", title: "收尾、记录明日第一步", anchor: .start(480), duration: 20, rule: .weekly([2,3,4,5,6]), starred: false),
                TemplateTask(id: "read", title: "阅读与睡前准备", anchor: .sleep(0), duration: 20, rule: RepeatRule(), starred: false)
            ]),
        BuiltInTemplate(
            id: "worker-flex-shift", audience: .worker, name: "轮班 / 弹性工作",
            summary: "围绕班次开始时间组织通勤、专注、收尾与恢复", suggestedSheetName: "弹性工作", colorHex: "F97316",
            tasks: [
                TemplateTask(id: "prepare", title: "出门准备与补水", anchor: .start(-90), duration: 20, rule: RepeatRule(), starred: false),
                TemplateTask(id: "commute", title: "通勤", anchor: .start(-50), duration: 35, rule: RepeatRule(), starred: false),
                TemplateTask(id: "handoff", title: "班前检查与交接", anchor: .start(0), duration: 20, rule: RepeatRule(), starred: true),
                TemplateTask(id: "focus", title: "本班次核心任务", anchor: .start(60), duration: 90, rule: RepeatRule(), starred: true),
                TemplateTask(id: "wrap", title: "交接与班后收尾", anchor: .start(360), duration: 25, rule: RepeatRule(), starred: false),
                TemplateTask(id: "recover", title: "恢复、运动或散步", anchor: .start(450), duration: 30, rule: RepeatRule(), starred: false)
            ])
    ]
}

enum BuiltInTemplateTarget: String, CaseIterable {
    case create = "新建计划表"
    case append = "追加当前表"
}

extension Store {
    func builtInTasks(template: BuiltInTemplate, variables: TemplateVariables, selectedIDs: Set<String>) throws -> [TaskItem] {
        let selected = template.tasks.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { throw DataValidationError.invalidTime("请至少选择一项模板任务") }
        return try selected.map { task in
            var item = try task.resolve(with: variables)
            item.id = UUID()
            item.createdOn = currentDay
            item.doneDays = []
            item.remindedDays = []
            item.endRemindedDays = []
            return item
        }.sorted { ($0.remindAt ?? Int.max) < ($1.remindAt ?? Int.max) }
    }

    @discardableResult
    func applyBuiltInTemplate(_ template: BuiltInTemplate, variables: TemplateVariables,
                              selectedIDs: Set<String>, target: BuiltInTemplateTarget) throws -> Int {
        let items = try builtInTasks(template: template, variables: variables, selectedIDs: selectedIDs)
        switch target {
        case .create:
            let sheet = PlanSheet(name: template.suggestedSheetName, colorHex: template.colorHex, tasks: items)
            sheets.append(sheet)
            activeSheetId = sheet.id
        case .append:
            guard let index = activeIndex else { throw DataValidationError.invalidSheet("", reason: "当前计划表不可用") }
            sheets[index].tasks.append(contentsOf: items)
        }
        return items.count
    }
}
