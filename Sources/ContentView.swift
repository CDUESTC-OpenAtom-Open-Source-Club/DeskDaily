import SwiftUI
import ServiceManagement

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

func lightenHex(_ hex: String, by amount: Double) -> String {
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    func lift(_ channel: UInt64) -> UInt64 { min(255, UInt64(Double(channel) + 255 * amount)) }
    return String(format: "%02lX%02lX%02lX",
                  lift((value >> 16) & 0xFF), lift((value >> 8) & 0xFF), lift(value & 0xFF))
}

/// 主题色跟随当前计划表，切换计划表即换装
enum Accent {
    static var start: Color { Color(hex: Store.shared.activeSheetColorHex) }
    static var end: Color { Color(hex: lightenHex(Store.shared.activeSheetColorHex, by: 0.22)) }
    static var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

func ruleIcon(_ rule: RepeatRule) -> String {
    switch rule.kind {
    case .daily: return "arrow.triangle.2.circlepath"
    case .once: return "1.circle"
    case .weekly: return "calendar"
    }
}

func ruleBadge(_ rule: RepeatRule) -> String? {
    switch rule.kind {
    case .daily: return nil
    case .once: return "仅今天"
    case .weekly:
        let set = rule.weekdays
        if set == [2, 3, 4, 5, 6] { return "工作日" }
        if set == [1, 7] { return "周末" }
        let names = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
        return "周" + set.sorted().compactMap { names[$0] }.joined()
    }
}

func ruleName(_ rule: RepeatRule) -> String {
    switch rule.kind {
    case .daily: return "每天"
    case .once: return "仅今天"
    case .weekly: return ruleBadge(rule) ?? "每周几"
    }
}

/// 打开带输入框的弹窗前先激活本应用，否则 ⌘V 会被前台应用的菜单栏抢走
func activateApp() {
    if #available(macOS 14.0, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct CardBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 各区块把自己的高度累加进来，窗口据此自适应高度
struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var newTitle = ""
    @State private var newRule = RepeatRule()
    @State private var newRemindMinutes: Int?
    @State private var newDuration: Int?
    @State private var showAddTime = false
    @State private var showAddRule = false
    @State private var settingsOpen = false
    @State private var aiOpen = false
    @State private var showSheetEditor = false
    @State private var sheetEditorIsNew = true
    @State private var confirmDeleteSheet = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            sheetBar
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            taskList
            addBarSection
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                CardBackground()
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onPreferenceChange(HeightKey.self) { h in
            WindowController.shared.fitHeight(to: h)
        }
        .popover(isPresented: $settingsOpen, arrowEdge: .bottom) {
            SettingsView()
        }
        .confirmationDialog("确定删除计划表「\(store.activeSheetName)」及其所有任务吗？",
                            isPresented: $confirmDeleteSheet, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.deleteActiveSheet() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 计划表切换栏

    private var sheetBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.sheets) { sheet in
                    Button {
                        store.activeSheetId = sheet.id
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(Color(hex: sheet.colorHex))
                            Text(sheet.name)
                            if sheet.id == store.activeSheetId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button { sheetEditorIsNew = true; showSheetEditor = true } label: {
                    Label("新建计划表…", systemImage: "plus")
                }
                Button { sheetEditorIsNew = false; showSheetEditor = true } label: {
                    Label("重命名 / 换颜色…", systemImage: "paintbrush")
                }
                Divider()
                Button(role: .destructive) { confirmDeleteSheet = true } label: {
                    Label("删除当前计划表", systemImage: "trash")
                }
                .disabled(store.sheets.count <= 1)
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Accent.start).frame(width: 8, height: 8)
                    Text(store.activeSheetName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $showSheetEditor, arrowEdge: .bottom) {
                SheetEditorView(isNew: sheetEditorIsNew)
            }
            Spacer()
            Text("\(store.visibleTasks.count) 项")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    // MARK: - 顶部：日期 + 进度环 + 菜单

    private var headerSection: some View {
        let header = store.dateHeader()
        let done = store.doneCount
        let total = store.visibleTasks.count
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(header.weekday)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Accent.gradient)
                    .kerning(2)
                Text(header.date)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                    Text("\(store.clockString()) · \(store.tzLabel())")
                }
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 6)
            progressRing(done: done, total: total)
            Button {
                activateApp()
                aiOpen = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Accent.gradient)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("AI 日程规划")
            .popover(isPresented: $aiOpen, arrowEdge: .bottom) {
                ChatView()
            }
            Menu {
                Button { activateApp(); settingsOpen = true } label: { Label("设置…", systemImage: "gearshape") }
                Button { store.resetToday() } label: { Label("重置今日勾选", systemImage: "arrow.counterclockwise") }
                Divider()
                Button(role: .destructive) { NSApp.terminate(nil) } label: { Label("退出 DeskDaily", systemImage: "power") }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, -4)
            .help("设置")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func progressRing(done: Int, total: Int) -> some View {
        let progress: CGFloat = total > 0 ? CGFloat(done) / CGFloat(total) : 0
        let showPercent = store.settings.progressMode == .percent
        let label = total > 0 ? (showPercent ? "\(Int((progress * 100).rounded()))%" : "\(done)") : "–"
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Accent.start, Accent.end], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
            Text(label)
                .font(.system(size: showPercent ? 10.5 : 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: 42, height: 42)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                store.settings.progressMode = showPercent ? .count : .percent
            }
        }
        .help(total > 0
              ? "今天已完成 \(done) / \(total)（\(Int((progress * 100).rounded()))%）· 点击切换计数/百分比"
              : "暂无任务")
    }

    // MARK: - 任务列表

    private var taskList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                if store.visibleTasks.isEmpty {
                    EmptyStateView()
                }
                ForEach(store.visibleTasks) { task in
                    TaskRow(task: task, done: store.isDone(task), nowMinutes: store.nowMinutes)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                }
            )
        }
    }

    // MARK: - 底部添加栏

    private var addBarSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Accent.gradient)
            TextField("添加任务…", text: $newTitle, onEditingChanged: { editing in
                if editing { activateApp() }
            })
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(addCurrent)
            if let minutes = newRemindMinutes {
                Button {
                    newRemindMinutes = nil
                    newDuration = nil
                } label: {
                    Text(addTimeChipText)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Accent.start.opacity(0.15)))
                        .foregroundColor(Accent.start)
                }
                .buttonStyle(.plain)
                .help("提醒时间 \(addTimeChipText)，点击清除")
            }
            Button {
                showAddTime = true
            } label: {
                Image(systemName: newRemindMinutes == nil ? "clock" : "clock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(newRemindMinutes == nil ? Color.secondary.opacity(0.6) : Accent.start)
            }
            .buttonStyle(.plain)
            .help("设置提醒时间（可选）")
            .popover(isPresented: $showAddTime, arrowEdge: .bottom) {
                TimePickerPopover(initialMinutes: newRemindMinutes ?? store.nowMinutes,
                                  initialDuration: newDuration ?? 0) { picked, duration in
                    newRemindMinutes = picked
                    newDuration = duration
                    showAddTime = false
                }
            }
            Button {
                showAddRule = true
            } label: {
                Image(systemName: ruleIcon(newRule))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(newRule.kind == .daily ? Accent.end : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("重复规则：\(ruleName(newRule))，点击修改")
            .popover(isPresented: $showAddRule, arrowEdge: .bottom) {
                RuleEditorView(initial: newRule) { rule in
                    newRule = rule
                    showAddRule = false
                }
            }
            Button(action: addCurrent) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        newTitle.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.secondary.opacity(0.35))
                            : AnyShapeStyle(Accent.gradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("添加")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var addTimeChipText: String {
        guard let m = newRemindMinutes else { return "" }
        guard let d = newDuration, d > 0 else { return store.timeString(m) }
        return "\(store.timeString(m))-\(store.timeString((m + d) % 1440))"
    }

    private func addCurrent() {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.addTask(title: t, rule: newRule, remindAt: newRemindMinutes, duration: newDuration)
        newTitle = ""
        newRemindMinutes = nil
        newDuration = nil
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Accent.gradient)
            Text("今天还没有任务")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.75))
            Text("在下方输入框添加任务\n完成后点击左侧圆圈打勾")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - 任务行

struct TaskRow: View {
    let task: TaskItem
    let done: Bool
    let nowMinutes: Int

    @EnvironmentObject var store: Store
    @State private var hovering = false
    @State private var isEditing = false
    @State private var editBuffer = ""
    @State private var showTimePicker = false
    @State private var showRuleEditor = false

    private var periodEnd: Int? {
        guard let s = task.remindAt, let d = task.durationMinutes else { return nil }
        return s + d
    }

    /// 正处于任务时段内（开始 ≤ 现在 < 结束）
    private var inPeriod: Bool {
        guard !done, let s = task.remindAt, let d = task.durationMinutes else { return false }
        return nowMinutes >= s && nowMinutes < s + d
    }

    private var isOverdue: Bool {
        guard !done, let s = task.remindAt else { return false }
        if let end = periodEnd { return nowMinutes > end }
        return nowMinutes > s + 1
    }

    private var timeChipText: String {
        guard let s = task.remindAt else { return "" }
        guard let e = periodEnd else { return store.timeString(s) }
        return "\(store.timeString(s))-\(store.timeString(e))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    store.toggleDone(task.id)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.8)
                        .frame(width: 22, height: 22)
                    if done {
                        Circle()
                            .fill(Accent.gradient)
                            .frame(width: 22, height: 22)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(done ? "点击取消完成" : "点击标记完成")

            if isEditing {
                TextField("任务标题", text: $editBuffer)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit(finishEdit)
            } else {
                titleView
            }

            Spacer(minLength: 0)

            if task.remindAt != nil, !isEditing {
                timeChip
            }
            if inPeriod && !isEditing {
                Text("进行中")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
            if hovering && !isEditing {
                Button {
                    withAnimation { store.delete(task.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("删除任务")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(inPeriod ? Color.green.opacity(0.10)
                      : (hovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { contextMenuItems }
        .popover(isPresented: $showTimePicker, arrowEdge: .trailing) {
            TimePickerPopover(initialMinutes: task.remindAt ?? store.nowMinutes,
                              initialDuration: task.durationMinutes ?? 0) { picked, duration in
                store.setRemind(task.id, minutes: picked, duration: duration)
                showTimePicker = false
            }
        }
        .popover(isPresented: $showRuleEditor, arrowEdge: .trailing) {
            RuleEditorView(initial: task.repeatRule) { rule in
                store.setRule(task.id, rule: rule)
                showRuleEditor = false
            }
        }
    }

    private var titleView: some View {
        HStack(spacing: 6) {
            Text(task.title)
                .font(.system(size: 13.5, weight: done ? .regular : .medium))
                .strikethrough(done, color: .secondary)
                .foregroundColor(done ? .secondary : .primary)
                .lineLimit(2)
            if let badge = ruleBadge(task.repeatRule) {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.16)))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture(count: 2) { startEditing() }
    }

    private var timeChip: some View {
        HStack(spacing: 3) {
            Image(systemName: inPeriod ? "clock.badge.checkmark" : (isOverdue ? "clock.badge.exclamationmark" : "clock"))
                .font(.system(size: 9, weight: .semibold))
            Text(timeChipText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(inPeriod ? Color.green.opacity(0.16)
                           : (isOverdue ? Color.red.opacity(0.14) : Color.secondary.opacity(0.13)))
        )
        .foregroundColor(inPeriod ? .green : (isOverdue ? .red : .secondary))
        .onTapGesture { activateApp(); showTimePicker = true }
        .help(inPeriod
              ? "进行中（\(timeChipText)），点击修改"
              : (isOverdue ? "已过时段，点击修改" : "提醒时间 \(timeChipText)，点击修改"))
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button { activateApp(); showTimePicker = true } label: {
            Label(task.remindAt == nil ? "设置提醒时间…" : "修改提醒时间…", systemImage: "clock")
        }
        if task.remindAt != nil {
            Button { store.setRemind(task.id, minutes: nil) } label: {
                Label("清除提醒时间", systemImage: "clock.slash")
            }
        }
        Button { startEditing() } label: { Label("修改标题", systemImage: "pencil") }
        Menu {
            Button("仅今天") { store.setRule(task.id, rule: RepeatRule.once(date: store.currentDay)) }
            Button("每天") { store.setRule(task.id, rule: RepeatRule()) }
            Button("工作日（周一至周五）") { store.setRule(task.id, rule: RepeatRule.weekly([2, 3, 4, 5, 6])) }
            Button("周末（周六、周日）") { store.setRule(task.id, rule: RepeatRule.weekly([1, 7])) }
            Divider()
            Button("自定义每周几…") { activateApp(); showRuleEditor = true }
        } label: {
            Label("重复规则（\(ruleName(task.repeatRule))）", systemImage: "repeat")
        }
        Divider()
        Button(role: .destructive) { store.delete(task.id) } label: {
            Label("删除任务", systemImage: "trash")
        }
    }

    private func startEditing() {
        editBuffer = task.title
        isEditing = true
    }

    private func finishEdit() {
        let t = editBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { store.rename(task.id, to: t) }
        isEditing = false
    }
}

// MARK: - 时间选择弹窗

struct TimePickerPopover: View {
    let initialMinutes: Int
    let initialDuration: Int
    let onPick: (Int?, Int?) -> Void

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    // 直接用「时/分」两个数字，不经系统 DatePicker（它固定按系统时区显示，
    // 在"北京时间"模式下会导致弹窗时间与卡片显示不一致）
    @State private var hour = 8
    @State private var minute = 0
    @State private var duration = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("提醒时间（\(store.tzShortLabel())）")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Menu {
                    ForEach(0..<24, id: \.self) { h in
                        Button(String(format: "%02d 时", h)) { hour = h }
                    }
                } label: {
                    Text(String(format: "%02d 时", hour))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(width: 70)
                }
                .fixedSize()
                Text(":")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
                Menu {
                    ForEach(0..<60, id: \.self) { m in
                        Button(String(format: "%02d 分", m)) { minute = m }
                    }
                } label: {
                    Text(String(format: "%02d 分", minute))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(width: 70)
                }
                .fixedSize()
            }
            Picker("时段时长", selection: $duration) {
                Text("无（单点提醒）").tag(0)
                ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { minutes in
                    Text("\(minutes) 分钟").tag(minutes)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Text(duration == 0
                 ? "到点提醒一次"
                 : "开始时提醒、结束时再提醒一次\n进行中的条目会亮绿色")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Button { onPick(nil, 0) } label: { Text("清除").foregroundColor(.red) }
                Button { dismiss() } label: { Text("取消") }
                Button {
                    onPick(hour * 60 + minute, duration)
                } label: { Text("确定").bold() }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(18)
        .frame(width: 224)
        .onAppear {
            hour = min(max(initialMinutes / 60, 0), 23)
            minute = min(max(initialMinutes % 60, 0), 59)
            duration = initialDuration
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var loginEnabled = false
    @State private var confirmClearAll = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var testSuccess = false

    private func clipboardString() -> String {
        NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func pasteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("把剪贴板内容粘贴进来（自动去掉首尾空格）")
    }

    private var testButton: some View {
        Button {
            runConnectionTest()
        } label: {
            HStack(spacing: 5) {
                if testing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "bolt.horizontal.circle")
                }
                Text(testing ? "测试中…" : "测试连接")
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(testing ? Color.secondary.opacity(0.12) : Accent.end.opacity(0.14))
            )
            .foregroundColor(testing ? Color.secondary : Accent.end)
        }
        .buttonStyle(.plain)
        .disabled(testing
                  || store.settings.aiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
                  || store.settings.aiModel.trimmingCharacters(in: .whitespaces).isEmpty)
        .help("向所填接口真实发送一条消息，校验能否正常对话")
    }

    private func runConnectionTest() {
        guard !testing else { return }
        testing = true
        testResult = nil
        let settings = store.settings
        let start = Date()
        Task { @MainActor in
            do {
                let reply = try await AIClient.shared.chat(
                    system: "You are a connection test.",
                    messages: [ChatMessage(role: "user", content: "请只回复四个字：连接成功")],
                    settings: settings,
                    timeout: 20)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                testSuccess = true
                testResult = "连接成功（\(ms)ms），模型回复：\(String(reply.prefix(30)))"
            } catch let urlError as URLError where urlError.code == .cannotConnectToHost
                || urlError.code == .cannotFindHost || urlError.code == .timedOut {
                testSuccess = false
                testResult = "连不上服务器：检查地址是否正确、本地模型服务是否已启动"
            } catch {
                testSuccess = false
                testResult = "失败：\(error.localizedDescription)"
            }
            testing = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.system(size: 14, weight: .bold))

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("时区", selection: $store.settings.tzMode) {
                        Text("跟随系统").tag(TZMode.system)
                        Text("北京时间").tag(TZMode.beijing)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("“今天”按此时区计算，跨 0 点自动刷新清单。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            } label: {
                Label("时间与时区（\(store.tzLabel())）", systemImage: "globe")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("显示", selection: $store.settings.windowMode) {
                        Text("悬浮置顶").tag(WindowMode.floating)
                        Text("贴附桌面").tag(WindowMode.desktop)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("悬浮置顶：始终显示在最前，点击/滚动/拖动均正常（推荐）。贴附桌面：嵌入桌面层，部分 Mac 环境下可能无法点击（实验性）。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            } label: {
                Label("窗口模式", systemImage: "macwindow")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("接口地址（chat/completions 完整 URL）", text: $store.settings.aiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        pasteButton { store.settings.aiBaseURL = clipboardString() }
                    }
                    HStack(spacing: 6) {
                        SecureField("API Key（本地模型可留空）", text: $store.settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        pasteButton { store.settings.apiKey = clipboardString() }
                    }
                    HStack(spacing: 6) {
                        TextField("模型名，如 glm-4.6", text: $store.settings.aiModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        pasteButton { store.settings.aiModel = clipboardString() }
                    }
                    testButton
                    if let testResult {
                        Label(testResult, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(testSuccess ? Color.green : Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                    }
                    Text("支持任意 OpenAI 兼容接口。智谱 https://api.z.ai/api/paas/v4/chat/completions；DeepSeek https://api.deepseek.com/chat/completions；本地 Ollama http://localhost:11434/v1/chat/completions。Key 只保存在本机。")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            } label: {
                Label("AI 助手", systemImage: "wand.and.stars")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $store.settings.memoryEnabled) {
                        Label("自动从对话中积累记忆", systemImage: "brain.head.profile")
                    }
                    if store.memories.isEmpty {
                        Text("暂无记忆。开启后，AI 会自动从 ✨ 对话中提取你的习惯与偏好，长期记住、越用越懂你。")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    } else {
                        Text("已记住 \(store.memories.count) 条（规划时自动参考）")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        ScrollView(showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(store.memories) { memory in
                                    HStack(spacing: 6) {
                                        Text("· \(memory.content)")
                                            .font(.system(size: 10.5))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        Button {
                                            store.deleteMemory(memory.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 110)
                        Button(role: .destructive) {
                            store.clearMemories()
                        } label: {
                            Label("清空记忆", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                    }
                }
            } label: {
                Label("AI 记忆", systemImage: "brain.head.profile")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("进度环", selection: $store.settings.progressMode) {
                        Text("完成数").tag(ProgressMode.count)
                        Text("百分比").tag(ProgressMode.percent)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("完成数显示已完成的任务数，百分比显示今日完成率；也可以直接点击卡片右上角的进度环切换。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            } label: {
                Label("进度环显示", systemImage: "gauge")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $store.settings.notifOn) {
                        Label("系统通知提醒", systemImage: "bell")
                    }
                    Toggle(isOn: $store.settings.soundOn) {
                        Label("提醒音效", systemImage: "speaker.wave.2")
                    }
                }
            } label: {
                Label("提醒方式", systemImage: "alarm")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $loginEnabled) {
                        Label("登录时自动启动", systemImage: "power")
                    }
                    .onChange(of: loginEnabled) { on in
                        if !LoginItem.set(on) { loginEnabled = false }
                    }
                    HStack {
                        Button { store.resetToday() } label: {
                            Label("重置今日勾选", systemImage: "arrow.counterclockwise")
                        }
                        Spacer()
                        Button { confirmClearAll = true } label: {
                            Label("清空当前计划表…", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            } label: {
                Label("通用", systemImage: "gearshape")
            }

            Text("DeskDaily v1.0 · 数据保存在本机\n~/Library/Application Support/DeskDaily/")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(width: 310)
        .onAppear { loginEnabled = LoginItem.isEnabled }
        .onChange(of: store.settings.tzMode) { _ in store.refreshNow() }
        .onChange(of: store.settings.windowMode) { _ in
            NotificationCenter.default.post(name: .deskDailyWindowModeChanged, object: nil)
        }
        .confirmationDialog("确定要清空「\(store.activeSheetName)」的全部任务吗？此操作不可恢复。",
                            isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("清空所有任务", role: .destructive) { store.clearAll() }
            Button("取消", role: .cancel) {}
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                NSLog("LoginItem error: \(error)")
                return false
            }
        }
        return false
    }
}

// MARK: - AI 规划对话

struct ChatView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var isWaiting = false
    @State private var errorMessage: String?
    @State private var detectedTasks: [AITask] = []
    @State private var showNoTasksHint = false

    private var configured: Bool {
        !store.settings.aiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !store.settings.aiModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().opacity(0.6)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if messages.isEmpty {
                            welcomeCard
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            bubble(message)
                        }
                        if isWaiting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("思考中…").font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !detectedTasks.isEmpty {
                            detectedCard
                        }
                        if showNoTasksHint && detectedTasks.isEmpty && !isWaiting {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("未识别到可导入的任务清单")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: requestJsonList) {
                                    Label("让 AI 重新输出清单", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .buttonStyle(.link)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: isWaiting) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear(perform: restoreHistory)
                .onChange(of: messages) { latest in
                    store.chatHistory = Array(latest.suffix(40))
                }
            }
            inputBar
        }
        .frame(width: 340, height: 460)
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.gradient)
            Text("AI 日程规划")
                .font(.system(size: 13, weight: .bold))
            if !configured {
                Text("未配置")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundColor(.orange)
            }
            Spacer()
            Button {
                messages = []
                store.chatHistory = []
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("开始新对话（长期记忆保留）")
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var welcomeCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26))
                .foregroundStyle(Accent.gradient)
            Text("AI 日程规划师")
                .font(.system(size: 13, weight: .bold))
            Text(configured
                 ? "告诉我你今天想完成什么，\n我会帮你拆解成带提醒时间的任务清单。"
                 : "先到 ⚙️ 设置 →「AI 助手」填写接口地址\n支持智谱 GLM / DeepSeek / 本地 Ollama")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if configured {
                Button(action: quickStart) {
                    Label("帮我规划今天", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == "user"
        HStack {
            if isUser { Spacer(minLength: 24) }
            Text(message.content)
                .font(.system(size: 12))
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isUser
                              ? AnyShapeStyle(Accent.gradient)
                              : AnyShapeStyle(Color.primary.opacity(0.08)))
                )
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private var detectedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("识别到 \(detectedTasks.count) 项 · 当前清单 \(store.visibleTasks.count) 项", systemImage: "checklist")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Accent.gradient)
            ForEach(detectedTasks) { task in
                HStack(spacing: 6) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(task.title)
                        .font(.system(size: 11))
                    Spacer()
                    if let time = task.remindAt {
                        let end = task.durationMinutes.map { duration in
                            store.timeString(((AIClient.minutes(fromHHMM: time) ?? 0) + duration) % 1440)
                        }
                        Text(end.map { "\(time)-\($0)" } ?? time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(action: replaceToday) {
                    Label("替换今日清单", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.link)
                .help("覆盖当前全部任务，以这份新清单为准")
                Button(action: appendToday) {
                    Label("追加", systemImage: "plus.circle")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.link)
                .help("保留现有任务，把这份清单追加到今天")
                Button(role: .destructive) {
                    detectedTasks = []
                } label: {
                    Text("忽略")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Accent.end.opacity(0.35), lineWidth: 1)
        )
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(configured ? "告诉 AI 你今天的安排…" : "请先在设置中配置 AI 接口", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(send)
                .disabled(!configured || isWaiting)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        input.trimmingCharacters(in: .whitespaces).isEmpty || !configured || isWaiting
                            ? AnyShapeStyle(Color.secondary.opacity(0.35))
                            : AnyShapeStyle(Accent.gradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || !configured || isWaiting)
            .help("发送")
        }
        .padding(12)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, configured, !isWaiting else { return }
        input = ""
        messages.append(ChatMessage(role: "user", content: text))
        fetchReply()
    }

    private func quickStart() {
        guard configured, !isWaiting else { return }
        messages.append(ChatMessage(role: "user", content: "帮我规划一下今天的任务安排"))
        fetchReply()
    }

    private func fetchReply() {
        isWaiting = true
        errorMessage = nil
        let history = messages
        let system = systemPrompt
        let settings = store.settings
        Task { @MainActor in
            do {
                let reply = try await AIClient.shared.chat(system: system, messages: history, settings: settings)
                messages.append(ChatMessage(role: "assistant", content: reply))
                detectedTasks = AIClient.parseTasks(from: reply)
                showNoTasksHint = detectedTasks.isEmpty
                isWaiting = false
                if store.settings.memoryEnabled {
                    extractMemories()
                }
            } catch {
                errorMessage = error.localizedDescription
                isWaiting = false
            }
        }
    }

    /// 恢复上次的对话记录
    private func restoreHistory() {
        if messages.isEmpty, !store.chatHistory.isEmpty {
            messages = store.chatHistory
        }
    }

    /// 异步从最近对话提取长期记忆（失败静默，不影响主流程）
    private func extractMemories() {
        let recent = messages.suffix(6).map { item in
            "\(item.role == "user" ? "用户" : "AI")：\(item.content)"
        }.joined(separator: "\n")
        let system = """
        你是记忆提取器。从对话里提取值得长期记住的用户信息（身份目标、作息习惯、偏好、固定安排等）。
        只输出一个 JSON 字符串数组（每条不超过 30 个字），没有值得记的就输出 []。
        """
        let settings = store.settings
        Task { @MainActor in
            guard let text = try? await AIClient.shared.chat(
                system: system,
                messages: [ChatMessage(role: "user", content: recent)],
                settings: settings,
                timeout: 30) else { return }
            var snippet = text
            if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end {
                snippet = String(text[start...end])
            }
            guard let array = (try? JSONSerialization.jsonObject(with: Data(snippet.utf8))) as? [String] else { return }
            for item in array { store.addMemory(item) }
        }
    }

    /// 模型没按要求输出清单时，一键要求它补发标准格式
    private func requestJsonList() {
        guard !isWaiting, configured else { return }
        messages.append(ChatMessage(
            role: "user",
            content: "请把最终的任务清单用 ```json 代码块重新输出一次，每个对象必须包含 title、remindAt（\"HH:mm\" 或 null）、repeatDaily（true/false）三个字段，代码块后不要再有其他内容。"))
        fetchReply()
    }

    /// 用 AI 的新清单整体覆盖今天
    private func replaceToday() {
        store.replaceAll(with: detectedTasks.map {
            (title: $0.title,
             repeatDaily: $0.repeatDaily,
             remindAt: $0.remindAt.flatMap { AIClient.minutes(fromHHMM: $0) },
             duration: $0.durationMinutes)
        })
        detectedTasks = []
    }

    /// 在现有任务后追加
    private func appendToday() {
        for task in detectedTasks {
            let minutes = task.remindAt.flatMap { AIClient.minutes(fromHHMM: $0) }
            let rule = task.repeatDaily ? RepeatRule() : RepeatRule.once(date: store.currentDay)
            store.addTask(title: task.title, rule: rule, remindAt: minutes, duration: task.durationMinutes)
        }
        detectedTasks = []
    }

    private var systemPrompt: String {
        let header = store.dateHeader()
        let existing = store.visibleTasks.map { task -> String in
            var text = store.isDone(task) ? "已完成✓ " : "未完成○ "
            text += task.title
            if let minutes = task.remindAt { text += "（\(store.timeString(minutes))）" }
            return text
        }.joined(separator: "；")
        let memoryText = store.settings.memoryEnabled
            ? store.memories.map { "· \($0.content)" }.joined(separator: "\n")
            : ""
        return """
        你是 DeskDaily 桌面清单的 AI 规划助手，帮用户规划今天（\(header.date) \(header.weekday)，现在 \(store.clockString())）的安排。
        对话规则：先简要了解用户今天的目标与空闲时段（总共不超过 3 个问题，每轮最多 2 个），语气简洁友好，不要长篇大论。
        信息足够后，给出简短的今日计划说明，并在最后单独输出 ```json 代码块。
        每个对象必须包含 title、remindAt、repeatDaily 三个字段（缺一不可，remindAt 没有就写 null）；如果是占用一段时间的事情，可加 durationMinutes（整数分钟）。格式示例：
        [{"title":"晨间锻炼","remindAt":"07:30","repeatDaily":false},{"title":"睡前阅读 20 分钟","remindAt":"22:00","repeatDaily":false,"durationMinutes":20}]
        要求：任务 3-8 条、按时间先后排序、时间用 24 小时制；代码块之后不要再输出任何内容。
        关于用户的长期记忆（规划时参考，让方案更贴合用户）：
        \(memoryText.isEmpty ? "（暂无）" : memoryText)
        用户当前的清单（每轮对话都同步最新状态，✓ 表示已完成）：\(existing.isEmpty ? "（暂无）" : existing)
        重要：你的输出将「整体替换」用户当前清单。请基于现有清单优化调整——该保留的保留、该调整的改时间改名称、多余的去掉，最终给出完整的新清单（不要只给增量）。
        """
    }
}

// MARK: - 计划表编辑器（新建 / 重命名 / 换颜色）

struct SheetEditorView: View {
    let isNew: Bool
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = SheetTheme.palette[0].hex

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "新建计划表" : "编辑计划表")
                .font(.system(size: 13, weight: .bold))
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("主题色（切换到此表时卡片同步换色）")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(SheetTheme.palette, id: \.hex) { item in
                    Button {
                        colorHex = item.hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 26, height: 26)
                            if colorHex == item.hex {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(.link)
                Spacer()
                Button(isNew ? "创建" : "保存") { save() }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .padding(16)
        .frame(width: 240)
        .onAppear {
            if isNew {
                colorHex = SheetTheme.palette[store.sheets.count % SheetTheme.palette.count].hex
                name = ""
            } else {
                name = store.activeSheetName
                colorHex = store.activeSheetColorHex
            }
        }
    }

    private func save() {
        if isNew {
            store.addSheet(name: name, colorHex: colorHex)
        } else if let id = store.activeSheetId {
            store.updateSheet(id, name: name, colorHex: colorHex)
        }
        dismiss()
    }
}

// MARK: - 重复规则编辑器

struct RuleEditorView: View {
    let initial: RepeatRule
    let onApply: (RepeatRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: RepeatKind = .daily
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]

    private let order: [(Int, String)] = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var body: some View {
        VStack(spacing: 12) {
            Text("重复规则")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Picker("", selection: $kind) {
                Text("仅今天").tag(RepeatKind.once)
                Text("每天").tag(RepeatKind.daily)
                Text("每周几").tag(RepeatKind.weekly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if kind == .weekly {
                HStack(spacing: 6) {
                    ForEach(order, id: \.0) { item in
                        Button {
                            toggle(item.0)
                        } label: {
                            Text(item.1)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle().fill(days.contains(item.0)
                                                  ? AnyShapeStyle(Accent.gradient)
                                                  : AnyShapeStyle(Color.primary.opacity(0.08)))
                                )
                                .foregroundColor(days.contains(item.0) ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("已选 \(days.count) 天")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 14) {
                Button("取消") { dismiss() }
                Button("确定") { apply() }
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.link)
        }
        .padding(16)
        .frame(width: 252)
        .onAppear {
            kind = initial.kind
            days = initial.weekdays.isEmpty ? [2, 3, 4, 5, 6] : initial.weekdays
        }
    }

    private func toggle(_ day: Int) {
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
    }

    private func apply() {
        switch kind {
        case .once:
            onApply(RepeatRule.once(date: Store.shared.currentDay))
        case .daily:
            onApply(RepeatRule())
        case .weekly:
            guard !days.isEmpty else { return }
            onApply(RepeatRule.weekly(days))
        }
    }
}
