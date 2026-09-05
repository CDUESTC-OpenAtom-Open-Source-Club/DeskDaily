import SwiftUI

// MARK: - 统计数据模型

enum StatsScope: String, CaseIterable, Identifiable {
    case currentSheet
    case allSheets

    var id: Self { self }
}

/// 热力图单日格子
struct DayCell: Equatable {
    let key: String        // yyyy-MM-dd
    let total: Int         // 当天范围内的活跃任务数
    let done: Int          // 当天已完成数
    let isToday: Bool
    let isFuture: Bool

    /// 当天完成率（0...1；total 为 0 时无意义）
    var rate: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// 统计页一次性算好的快照（重计算全部集中在 Store，UI 只读结果）
struct StatsSnapshot {
    let todayKey: String
    let totalCompletions: Int   // 累计完成次数（全部历史）
    let weekDone: Int           // 本周（周一至今）完成数
    let weekTotal: Int          // 本周活跃任务数
    let longestStreak: Int      // 所有任务中最长的连续完成天数
    let weeks: [[DayCell]]      // 每列一周（周一开头），最后一列含今天
    let hasData: Bool

    var weekRatePercent: Int? {
        weekTotal > 0 ? Int((Double(weekDone) / Double(weekTotal) * 100).rounded()) : nil
    }
}

// MARK: - Store 统计扩展

extension Store {
    /// 统计范围对应的计划表；当前表始终只取当前激活表。
    func statsSheets(scope: StatsScope) -> [PlanSheet] {
        switch scope {
        case .currentSheet:
            return activeSheet.map { [$0] } ?? []
        case .allSheets:
            return sheets
        }
    }

    func statsScopeTitle(_ scope: StatsScope) -> String {
        switch scope {
        case .currentSheet:
            return activeSheetName
        case .allSheets:
            return "全部计划表"
        }
    }

    // MARK: 日历辅助（dayKey 字符串加减天）

    // 日期辅助（date/dayKey偏移/weekday/标签）已抽取到 Store.swift + OccurrenceKit，与测试同源

    /// 本周周一的 dayKey
    func mondayKeyOfWeek() -> String {
        let offset = (weekdayNow() + 5) % 7   // 周一=0 … 周日=6
        return dayKey(byAddingDays: -offset, toKey: currentDay) ?? currentDay
    }

    /// 统计口径的"该天活跃"：重复规则命中，且该天不早于任务创建日
    /// （只影响历史统计的公平性，不改 visibleTasks 的展示口径）
    func wasActive(_ task: TaskItem, onDay key: String, weekday: Int) -> Bool {
        StatsCore.wasActive(task, onDay: key, weekday: weekday)
    }

    /// 某天范围内的活跃任务数 / 已完成数（口径委托纯函数 StatsCore，与测试同源）
    func dayCounts(key: String, weekday: Int, scope: StatsScope = .currentSheet) -> (total: Int, done: Int) {
        if scope == .allSheets {
            return StatsCore.dayCounts(sheets: statsSheets(scope: scope), dayKey: key, weekday: weekday)
        }
        return StatsCore.dayCounts(sheet: activeSheet, dayKey: key, weekday: weekday)
    }

    // MARK: 连续打卡

    /// 当前连续完成天数：今天已完成则含今天，否则从昨天起算；
    /// 不活跃的日期跳过（不算断档），遇到"活跃但未完成"即停；once 任务 0/1 简单处理
    func streak(of task: TaskItem) -> Int {
        if task.repeatRule.kind == .once {
            return task.doneDays.contains(task.repeatRule.date) ? 1 : 0
        }
        var count = 0
        var key = currentDay
        if task.doneDays.contains(key) { count = 1 }
        var steps = 0
        while steps < 800 {   // 防御上限，正常首个断档就会停
            steps += 1
            guard let prev = dayKey(byAddingDays: -1, toKey: key) else { break }
            key = prev
            if !task.createdOn.isEmpty, key < task.createdOn { break }
            guard task.repeatRule.isActive(on: key, weekday: weekday(ofDayKey: key)) else { continue }
            if task.doneDays.contains(key) {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// 历史最佳连续完成天数（从首个完成日/创建日起逐日扫描）
    func bestStreak(of task: TaskItem) -> Int {
        if task.repeatRule.kind == .once {
            return task.doneDays.contains(task.repeatRule.date) ? 1 : 0
        }
        guard let firstDone = task.doneDays.sorted().first else { return 0 }
        var key = !task.createdOn.isEmpty && task.createdOn < firstDone ? task.createdOn : firstDone
        var best = 0
        var run = 0
        var steps = 0
        while key <= currentDay, steps < 4000 {
            steps += 1
            if task.repeatRule.isActive(on: key, weekday: weekday(ofDayKey: key)) {
                if task.doneDays.contains(key) {
                    run += 1
                    if run > best { best = run }
                } else {
                    run = 0
                }
            }
            guard let next = dayKey(byAddingDays: 1, toKey: key) else { break }
            key = next
        }
        return best
    }

    // MARK: 快照与报告（重计算集中在这里，UI 只读）

    /// 统计快照：三张卡片数字 + 最近 N 周热力图
    func buildStatsSnapshot(weeks weekCount: Int = 26, scope: StatsScope = .currentSheet) -> StatsSnapshot {
        let today = currentDay
        let monday = mondayKeyOfWeek()
        var columns: [[DayCell]] = []
        var weekDone = 0
        var weekTotal = 0
        for w in 0..<max(weekCount, 1) {
            // 第 0 列 = weekCount-1 周前的周一，最后一列 = 本周一（含今天与本周未来占位）
            guard let weekStart = dayKey(byAddingDays: 7 * (w - weekCount + 1), toKey: monday) else { continue }
            var column: [DayCell] = []
            for d in 0..<7 {
                guard let key = dayKey(byAddingDays: d, toKey: weekStart) else { continue }
                if key > today {
                    column.append(DayCell(key: key, total: 0, done: 0, isToday: false, isFuture: true))
                } else {
                    let counts = dayCounts(key: key, weekday: weekday(ofDayKey: key), scope: scope)
                    column.append(DayCell(key: key, total: counts.total, done: counts.done,
                                          isToday: key == today, isFuture: false))
                    if key >= monday {
                        weekTotal += counts.total
                        weekDone += counts.done
                    }
                }
            }
            columns.append(column)
        }
        var totalCompletions = 0
        var longest = 0
        var taskCount = 0
        for sheet in statsSheets(scope: scope) {
            for task in sheet.tasks {
                taskCount += 1
                totalCompletions += task.doneDays.filter { $0 <= today }.count
                let best = bestStreak(of: task)
                if best > longest { longest = best }
            }
        }
        return StatsSnapshot(todayKey: today,
                             totalCompletions: totalCompletions,
                             weekDone: weekDone,
                             weekTotal: weekTotal,
                             longestStreak: longest,
                             weeks: columns,
                             hasData: taskCount > 0 || totalCompletions > 0)
    }

    /// 本地每周复盘报告（Markdown，纯本地拼字符串，不调 AI）
    func weeklyReportMarkdown(scope: StatsScope = .currentSheet) -> String {
        let monday = mondayKeyOfWeek()
        let dayNames = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日"]
        var dayLines: [String] = []
        var sumTotal = 0
        var sumDone = 0
        var key = monday
        while key <= currentDay {
            let weekday = weekday(ofDayKey: key)
            let counts = dayCounts(key: key, weekday: weekday, scope: scope)
            sumTotal += counts.total
            sumDone += counts.done
            let rate = counts.total > 0
                ? "\(Int((Double(counts.done) / Double(counts.total) * 100).rounded()))%（\(counts.done)/\(counts.total)）"
                : "无任务"
            dayLines.append("- 周\(dayNames[weekday] ?? "") \(shortDayLabel(key))：\(rate)")
            guard let next = dayKey(byAddingDays: 1, toKey: key) else { break }
            key = next
        }
        var topTask: (name: String, count: Int)? = nil
        var longestTask: (name: String, days: Int)? = nil
        for sheet in statsSheets(scope: scope) {
            for task in sheet.tasks {
                let weekHits = task.doneDays.filter { $0 >= monday && $0 <= currentDay }.count
                if weekHits > (topTask?.count ?? 0) { topTask = (task.title, weekHits) }
                let best = bestStreak(of: task)
                if best > (longestTask?.days ?? 0) { longestTask = (task.title, best) }
            }
        }
        var lines: [String] = []
        lines.append("# DeskDaily 每周复盘（\(statsScopeTitle(scope)) · \(shortDayLabel(monday)) - \(shortDayLabel(currentDay))）")
        lines.append("")
        let weekPct = sumTotal > 0 ? Int((Double(sumDone) / Double(sumTotal) * 100).rounded()) : 0
        lines.append("本周共完成 \(sumDone)/\(sumTotal) 项，完成率 \(weekPct)%。")
        lines.append("")
        lines.append("## 每日完成率")
        lines.append(contentsOf: dayLines.isEmpty ? ["- 本周暂无记录"] : dayLines)
        lines.append("")
        lines.append("## 亮点")
        if let top = topTask, top.count > 0 {
            lines.append("- 打卡最多：「\(top.name)」本周完成 \(top.count) 次")
        } else {
            lines.append("- 本周暂无打卡记录")
        }
        if let longest = longestTask, longest.days > 0 {
            lines.append("- 最长连胜：「\(longest.name)」连续 \(longest.days) 天")
        } else {
            lines.append("- 暂无连续打卡记录")
        }
        return lines.joined(separator: "\n")
    }

    /// 今日清单 Markdown（「导出今日 Markdown」用）
    func todayMarkdown() -> String {
        let header = dateHeader()
        let tasks = visibleTasks
        var lines: [String] = []
        lines.append("# DeskDaily 今日清单（\(header.date) \(header.weekday)）")
        lines.append("")
        lines.append("计划表：\(activeSheetName)")
        if tasks.isEmpty {
            lines.append("")
            lines.append("（今天还没有任务）")
            return lines.joined(separator: "\n")
        }
        lines.append("")
        for task in tasks {
            let box = isDone(task) ? "x" : " "
            let time = task.remindAt.map { "（\(timeString($0))）" } ?? ""
            lines.append("- [\(box)] \(task.title)\(time)")
        }
        lines.append("")
        let done = doneCount
        let pct = Int((Double(done) / Double(tasks.count) * 100).rounded())
        lines.append("> 今日完成 \(done)/\(tasks.count)（\(pct)%）")
        return lines.joined(separator: "\n")
    }

    /// 睡前复盘：发给 AI 的开场消息（今日完成情况汇总，走 ChatView 的 systemPrompt）
    func todayReviewMessage() -> String {
        let tasks = visibleTasks
        let done = tasks.filter { isDone($0) }
        let undone = tasks.filter { !isDone($0) }
        let pct = tasks.isEmpty ? 0 : Int((Double(done.count) / Double(tasks.count) * 100).rounded())
        var lines: [String] = []
        lines.append("请帮我复盘今天（\(monthDayLabel(currentDay))）：共 \(tasks.count) 项任务，已完成 \(done.count) 项，完成率 \(pct)%。")
        if !done.isEmpty {
            lines.append("已完成：" + done.map { "「\($0.title)」" }.joined(separator: "、"))
        }
        if !undone.isEmpty {
            lines.append("未完成：" + undone.map { "「\($0.title)」" }.joined(separator: "、"))
        }
        lines.append("请简要点评我的今天：先肯定亮点，再给一条明天就能执行的小建议。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 简易 Markdown 渲染（行内语法 + 保留换行），失败降级纯文本

func markdownInline(_ content: String) -> AttributedString {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    if let parsed = try? AttributedString(markdown: content, options: options) {
        return parsed
    }
    return AttributedString(content)
}

// MARK: - 26 周热力图（列=周，行=周一…周日）

struct HeatmapView: View {
    let weeks: [[DayCell]]

    private let cell: CGFloat = 10
    private let gap: CGFloat = 2

    /// 完成率 → 主题色五档透明度；无任务浅灰、未来日期更浅的占位灰
    private func levelColor(_ day: DayCell) -> Color {
        if day.isFuture { return Color.primary.opacity(0.04) }
        if day.total == 0 { return Color.primary.opacity(0.07) }
        let accent = Accent.start
        switch day.rate {
        case ..<0.001: return accent.opacity(0.14)
        case 0.001...0.25: return accent.opacity(0.28)
        case 0.25...0.5: return accent.opacity(0.46)
        case 0.5...0.75: return accent.opacity(0.66)
        default: return accent.opacity(0.9)
        }
    }

    var body: some View {
        Canvas { ctx, _ in
            for (col, week) in weeks.enumerated() {
                for (row, day) in week.enumerated() {
                    let x = CGFloat(col) * (cell + gap)
                    let y = CGFloat(row) * (cell + gap)
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(levelColor(day)))
                    if day.isToday {
                        let border = Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3)
                        ctx.stroke(border, with: .color(Accent.start.opacity(0.9)), lineWidth: 1.2)
                    }
                }
            }
        }
        .frame(width: CGFloat(weeks.count) * (cell + gap) - gap,
               height: 7 * (cell + gap) - gap)
        .help("最近 \(weeks.count) 周完成热力图 · 颜色越深当天完成率越高")
    }
}

// MARK: - 统计页（sheetBar 右端「N 项」弹出）

struct StatisticsView: View {
    @EnvironmentObject var store: Store
    @State private var scope: StatsScope = .currentSheet
    @State private var snapshot: StatsSnapshot? = nil
    @State private var reportMarkdown: String? = nil
    @State private var aiComment: String? = nil
    @State private var aiWaiting = false
    @State private var aiRequestToken = 0
    @State private var aiError: String? = nil
    @State private var toast: String? = nil
    @State private var toastToken = 0

    init() {
        // 打开即有数据（离屏渲染 / 真实首帧不空白），onAppear 再按最新状态刷新
        _snapshot = State(initialValue: Store.shared.buildStatsSnapshot())
    }

    private var aiConfigured: Bool {
        !store.settings.aiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !store.settings.aiModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var scopeTitle: String {
        store.statsScopeTitle(scope)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(scopeTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Picker("统计范围", selection: $scope) {
                        Text("当前表").tag(StatsScope.currentSheet)
                        Text("全部").tag(StatsScope.allSheets)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 134)
                }
                if let s = snapshot, s.hasData {
                    statCards(s)
                    HeatmapView(weeks: s.weeks)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    legend
                    Divider().opacity(0.6)
                    reportSection
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 28))
                            .foregroundStyle(Accent.gradient)
                        Text("暂无统计数据")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.75))
                        Text("添加任务并完成后\n这里会出现你的热力图与周报")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380, height: 420)
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { refreshStatistics() }
        .onChange(of: scope) { _ in refreshStatistics() }
        .onChange(of: store.sheets) { _ in refreshStatistics() }
        .onChange(of: store.activeSheetId) { _ in refreshStatistics() }
        .onChange(of: store.currentDay) { _ in refreshStatistics() }
    }

    // MARK: 三张统计卡片

    private func statCards(_ s: StatsSnapshot) -> some View {
        HStack(spacing: 8) {
            statCard(value: "\(s.totalCompletions)", caption: "累计完成（次）")
            statCard(value: s.weekRatePercent.map { "\($0)%" } ?? "–", caption: "本周完成率")
            statCard(value: "\(s.longestStreak)", caption: "最长连胜（天）")
        }
    }

    private func statCard(value: String, caption: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Accent.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: 图例

    private var legend: some View {
        HStack(spacing: 5) {
            Text("少")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            ForEach([0.14, 0.28, 0.46, 0.66, 0.9], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Accent.start.opacity(opacity))
                    .frame(width: 8, height: 8)
            }
            Text("多")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text("本页数据均来自本机记录")
                .font(.system(size: 8.5))
                .foregroundColor(.secondary.opacity(0.85))
        }
    }

    // MARK: 每周复盘区

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每周复盘")
                .font(.system(size: 12, weight: .bold))
            HStack(spacing: 10) {
                Button(action: generateReport) {
                    Label("生成本周报告", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.link)
                .hoverPointing()
                .help("本地汇总本周（周一至今）的完成率、打卡与连胜，生成 Markdown")
                if aiConfigured {
                    Button(action: runAIComment) {
                        HStack(spacing: 4) {
                            if aiWaiting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(aiWaiting ? "AI 点评中…" : "AI 点评")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.link)
                    .hoverPointing()
                    .disabled(aiWaiting)
                    .help("把本地周报发给已配置的模型，请它简短点评")
                }
                Spacer(minLength: 0)
                Button(action: exportToday) {
                    Label("导出今日 Markdown", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.link)
                .hoverPointing()
                .help("把今日清单+完成情况生成 Markdown 并复制到剪贴板")
            }
            if let reportMarkdown {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reportMarkdown)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text("生成于 \(store.clockString()) · 纯本地汇总")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer(minLength: 0)
                        Button {
                            copyToClipboard(reportMarkdown)
                            showToast("周报已复制到剪贴板")
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .buttonStyle(.link)
                        .hoverPointing()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .transition(.opacity)
            }
            if let aiError {
                Label(aiError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let aiComment {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI 点评", systemImage: "wand.and.stars")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Accent.gradient)
                    Text(markdownInline(aiComment))
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Accent.start.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Accent.end.opacity(0.3), lineWidth: 1)
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: 动作

    private func generateReport() {
        withDDAnimation {
            aiComment = nil
            aiError = nil
            reportMarkdown = store.weeklyReportMarkdown(scope: scope)
        }
    }

    private func runAIComment() {
        guard !aiWaiting else { return }
        let report = reportMarkdown ?? store.weeklyReportMarkdown(scope: scope)
        if reportMarkdown == nil { reportMarkdown = report }
        aiWaiting = true
        aiRequestToken += 1
        let requestToken = aiRequestToken
        aiError = nil
        aiComment = nil
        let settings = store.settings
        Task { @MainActor in
            do {
                let reply = try await AIClient.shared.chat(
                    system: "你是复盘教练，简短点评3-5句，语气真诚，先肯定亮点再给一条可执行建议。",
                    messages: [ChatMessage(role: "user", content: report)],
                    settings: settings,
                    apiKey: store.apiKey,
                    timeout: 60)
                withDDAnimation {
                    guard aiRequestToken == requestToken else { return }
                    aiComment = reply
                }
            } catch {
                guard aiRequestToken == requestToken else { return }
                aiError = "AI 点评失败：\(error.localizedDescription)"
            }
            guard aiRequestToken == requestToken else { return }
            aiWaiting = false
        }
    }

    private func exportToday() {
        copyToClipboard(store.todayMarkdown())
        showToast("今日 Markdown 已复制到剪贴板")
    }

    private func refreshStatistics() {
        aiRequestToken += 1
        aiWaiting = false
        snapshot = store.buildStatsSnapshot(scope: scope)
        reportMarkdown = nil
        aiComment = nil
        aiError = nil
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func showToast(_ message: String) {
        withDDAnimation { toast = message }
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard toastToken == token else { return }
            withDDAnimation { toast = nil }
        }
    }
}
