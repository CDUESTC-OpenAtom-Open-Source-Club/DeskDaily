import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

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

// MARK: - 动效辅助（全局统一；系统开启"减弱动态效果"时自动降级为短 crossfade）

enum DDMotion {
    /// 系统辅助功能：减弱动态效果（等价于 SwiftUI 的 accessibilityReduceMotion）
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 统一 spring 动画（Reduce Motion 时为 0.18s 渐变 crossfade）
    static var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    /// 任务行增删动效：插入自底部滑入+淡入，删除向右滑出
    static var taskRowTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}

/// 全局统一动效（读取辅助功能设置，全局统一使用）
var ddAnimation: Animation { DDMotion.animation }

/// 所有会引发列表/布局变化的状态修改统一走这里
func withDDAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
    try withAnimation(DDMotion.animation, body)
}

// MARK: - 悬停光标辅助（可点击元素显示手形光标，可选微放大）

struct HoverPointerModifier: ViewModifier {
    var magnify: Bool = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(magnify && hovering ? 1.05 : 1)
            .animation(DDMotion.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: hovering)
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

extension View {
    /// 可点击元素悬停显示手形光标；magnify 为 true 时悬停微放大 1.05
    func hoverPointing(magnify: Bool = false) -> some View {
        modifier(HoverPointerModifier(magnify: magnify))
    }
}

// MARK: - “现在”指示线（主题色渐变横线 + 圆点 + HH:mm 标签）

struct NowLineView: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Accent.start)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Accent.start)
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(colors: [Accent.start.opacity(0.85), Accent.end.opacity(0.08)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 1.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .accessibilityLabel("现在 \(label)")
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

/// 迷你胶囊里的小进度环（无文字，跟随完成度）
struct MiniRingView: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Accent.start, Accent.end], center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
    }
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
    @State private var templateCatalogOpen = false
    @State private var showSheetEditor = false
    @State private var sheetEditorIsNew = true
    @State private var confirmDeleteSheet = false
    @State private var doneExpanded = false
    @State private var showUndoToast = false
    @State private var undoToastToken = 0
    @State private var statsOpen = false
    /// 全部完成庆祝：token 驱动粒子喷发，celebrationAt 记录完成时刻
    @State private var celebrateToken = 0
    @State private var celebrationAt: Date? = nil
    @State private var ringPulse = false
    /// 周视图：0 = 今天，1 = 明天（最多 1）
    @State private var viewOffset = 0
    /// 切换视角的滑动方向（明天从右进，今天从左进）
    @State private var slideForward = true
    /// 自然语言快速添加：当前解析结果 + 芯片移除/回填签名
    @State private var addParse: QuickAddParse? = nil
    @State private var appliedTimeToken: String? = nil
    @State private var appliedDurationToken: String? = nil
    @State private var appliedRuleToken: String? = nil
    @State private var dismissedTimeToken: String? = nil
    @State private var dismissedDurationToken: String? = nil
    @State private var dismissedRuleToken: String? = nil
    /// 通用轻提示（存模板 / 明天视角点勾等）
    @State private var infoToast: String? = nil
    @State private var infoToastToken = 0
    /// ⌘N「新任务」聚焦添加输入框
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        ZStack {
            if store.settings.collapsed {
                miniCapsule
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                expandedCard
                    .transition(.opacity)
            }
        }
        .animation(ddAnimation, value: store.settings.collapsed)
        .background(
            ZStack {
                CardBackground()
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Accent.start.opacity(store.settings.collapsed ? 0.45 : 0.15), lineWidth: 1)
        )
        .onHover { WindowController.shared.noteCardHover($0) }
        .onPreferenceChange(HeightKey.self) { h in
            WindowController.shared.fitHeight(to: h)
        }
        .overlay(alignment: .bottom) {
            if showUndoToast, let deleted = store.lastDeleted {
                undoToastView(title: deleted.task.title)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let infoToast {
                Label(infoToast, systemImage: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            Capsule().fill(.ultraThinMaterial)
                            Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: store.lastDeleted) { info in
            if info != nil {
                undoToastToken += 1
                withDDAnimation { showUndoToast = true }
                let token = undoToastToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard undoToastToken == token else { return }
                    withDDAnimation { showUndoToast = false }
                }
            } else {
                withDDAnimation { showUndoToast = false }
            }
        }
        .onChange(of: allDoneToday) { done in
            // false → true 跳变时庆祝；应用启动时已全部完成不会触发
            guard done else { return }
            celebrateAllDone()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deskDailyOpenReview)) { _ in
            // 常驻 AI 面板接住复盘内容；未配置时保留为草稿，不会静默丢失。
            WindowController.shared.showAIPanel(autoSend: store.todayReviewMessage())
        }
        .onReceive(NotificationCenter.default.publisher(for: .deskDailyFocusAddField)) { _ in
            // 菜单「新任务 ⌘N」→ 聚焦添加输入框
            addFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deskDailyTimeConflict)) { note in
            // 时段冲突检测命中 → 轻提示（相关任务的时间胶囊同时在黄色闪烁）
            if let title = note.userInfo?["title"] as? String {
                showInfoToast("⚠️ 与「\(title)」时间重叠")
            }
        }
        .confirmationDialog("确定删除计划表「\(store.activeSheetName)」及其所有任务吗？",
                            isPresented: $confirmDeleteSheet, titleVisibility: .visible) {
            Button("删除", role: .destructive) { withDDAnimation { store.deleteActiveSheet() } }
            Button("取消", role: .cancel) {}
        }
    }

    /// 折叠态窗口的圆角（56 高窗口取 28 即胶囊形）
    private var cardCornerRadius: CGFloat { store.settings.collapsed ? 28 : 22 }

    /// 完整卡片内容（未折叠时的主体）
    private var expandedCard: some View {
        VStack(spacing: 0) {
            headerSection
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            sheetBar
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            focusBarSection
            taskList
            addBarSection
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 迷你折叠胶囊（双击标题区折叠 / 双击胶囊展开）

    /// 双击切换折叠：窗口尺寸动画（顶边不动）+ 内容 crossfade；状态写入设置（重启保持）
    private func toggleCollapsed() {
        let to = !store.settings.collapsed
        WindowController.shared.setCollapsed(to)
        withDDAnimation { store.settings.collapsed = to }
    }

    private var miniProgress: CGFloat {
        let total = store.visibleTasks.count
        guard total > 0 else { return 0 }
        return CGFloat(store.doneCount) / CGFloat(total)
    }

    /// 下一件事摘要：最近的未完成定时任务（已全过点则取最早一个），无任务显示“今日空闲”
    private var miniNextLine: String {
        let undone = store.visibleTasks.filter { !store.isDone($0) }
        guard !undone.isEmpty else { return "今日空闲" }
        let timed = undone.filter { $0.remindAt != nil }.sorted { ($0.remindAt ?? 0) < ($1.remindAt ?? 0) }
        let next = timed.first { ($0.remindAt ?? 0) >= store.nowMinutes } ?? timed.first ?? undone[0]
        let title = next.title.count > 8 ? String(next.title.prefix(8)) + "…" : next.title
        if let m = next.remindAt { return "\(store.timeString(m)) \(title)" }
        return title
    }

    private var miniCapsule: some View {
        HStack(spacing: 7) {
            MiniRingView(progress: miniProgress)
            Text("\(store.doneCount)/\(store.visibleTasks.count)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
            Circle()
                .fill(Accent.start.opacity(0.45))
                .frame(width: 3, height: 3)
            if let session = store.focusSession {
                // 专注进行中：摘要位置显示番茄钟倒计时（每秒刷新）
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = session.pausedRemaining
                        ?? max(Int(session.endsAt.timeIntervalSince(Store.now())), 0)
                    Text("⏱ \(FocusBarView.mmss(remaining))")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Accent.start)
                }
            } else {
                Text(miniNextLine)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Accent.start.opacity(0.06))
            }
        )
        .overlay(Capsule().strokeBorder(Accent.start.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture(count: 2) { toggleCollapsed() }
        .help("双击展开 · \(store.activeSheetName)（可直接拖动）")
    }

    // MARK: - 计划表切换栏

    private var sheetBar: some View {
        HStack(spacing: 8) {
            // 今天 | 明天 周视图切换（带滑动方向）
            Picker("视角", selection: Binding(
                get: { viewOffset },
                set: { newValue in
                    guard newValue != viewOffset else { return }
                    slideForward = newValue > viewOffset
                    withDDAnimation { viewOffset = newValue }
                })) {
                Text("今天").tag(0)
                Text("明天").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 86)
            .labelsHidden()
            .onChange(of: viewOffset) { offset in
                // 切视角重置草稿：明天视角新任务默认「仅明天」
                doneExpanded = false
                withDDAnimation {
                    newRule = offset == 1
                        ? RepeatRule.once(date: store.tomorrowKey() ?? store.currentDay)
                        : RepeatRule()
                }
            }
            Menu {
                ForEach(store.sheets) { sheet in
                    Button {
                        withDDAnimation { store.activeSheetId = sheet.id }
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
                Button {
                    activateApp()
                    templateCatalogOpen = true
                } label: {
                    Label("浏览内置模板…", systemImage: "square.grid.2x2")
                }
                Divider()
                // 用户模板库
                Button {
                    store.saveCurrentAsTemplate()
                    showInfoToast("已存为模板「\(store.templates.last?.name ?? "")」")
                } label: {
                    Label("存为模板", systemImage: "square.and.arrow.down")
                }
                Menu {
                    if store.templates.isEmpty {
                        Button("暂无模板，先把当前表存为模板") {}.disabled(true)
                    } else {
                        ForEach(store.templates) { tpl in
                            Button {
                                withDDAnimation { store.instantiateTemplate(tpl.id) }
                                showInfoToast("已从模板新建「\(tpl.name)」")
                            } label: {
                                Text(tpl.name)
                            }
                        }
                    }
                } label: {
                    Label("从模板新建", systemImage: "doc.on.doc")
                }
                Menu {
                    ForEach(store.templates) { tpl in
                        Button(role: .destructive) {
                            withDDAnimation { store.deleteTemplate(tpl.id) }
                        } label: {
                            Text(tpl.name)
                        }
                    }
                } label: {
                    Label("删除模板", systemImage: "trash")
                }
                .disabled(store.templates.isEmpty)
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
                        .lineLimit(1)
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
            .popover(isPresented: $templateCatalogOpen, arrowEdge: .bottom) {
                TemplateCatalogView()
            }
            Spacer()
            Button {
                statsOpen = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(store.visibleTasks.count) 项")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .hoverPointing()
            .help("任务统计 · 26 周热力图 · 每周复盘")
            .popover(isPresented: $statsOpen, arrowEdge: .bottom) {
                StatisticsView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    // MARK: - 顶部：日期 + 进度环 + 菜单

    /// 专注进行时的番茄钟条（sheetBar 下方）
    @ViewBuilder
    private var focusBarSection: some View {
        if store.focusSession != nil {
            FocusBarView()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var headerSection: some View {
        let header = store.dateHeader(offset: viewOffset)
        let done = viewOffset == 0 ? store.doneCount : 0
        let total = store.visibleTasks(offset: viewOffset).count
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(header.weekday)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Accent.gradient)
                        .kerning(2)
                    if viewOffset == 1 {
                        Text("明天")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Accent.start.opacity(0.15)))
                            .foregroundColor(Accent.start)
                    }
                }
                Text(header.date)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(store.dayPeriod().greeting)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                    Text("\(store.clockString()) · \(store.tzLabel())")
                }
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 6)
            progressRing(done: done, total: total)
                .scaleEffect(ringPulse ? 1.16 : 1)
                .overlay {
                    // 全部完成时从环心喷出的彩色粒子（Reduce Motion 时自动跳过）
                    CelebrationBurst(token: celebrateToken)
                        .frame(width: 300, height: 220)
                        .allowsHitTesting(false)
                }
            Button {
                WindowController.shared.showAIPanel()
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Accent.gradient)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverPointing()
            .help("AI 日程规划")
            Menu {
                Button { WindowController.shared.showSettingsPanel() } label: { Label("设置…", systemImage: "gearshape") }
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
        // 双击标题空白处：折叠为迷你胶囊 / 展开（折叠态记忆，重启保持）
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { toggleCollapsed() }
        .help("双击折叠为迷你胶囊")
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
        .hoverPointing(magnify: true)
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                store.settings.progressMode = showPercent ? .count : .percent
            }
        }
        .help(total > 0
              ? "今天已完成 \(done) / \(total)（\(Int((progress * 100).rounded()))%）· 点击切换计数/百分比"
              : "暂无任务")
    }

    // MARK: - 任务列表（未完成在上；“现在”线插在定时未完成序列中；已完成折叠在底部）

    /// 今日任务是否全部完成（total > 0 且 done == total；庆祝仅限今天视角）
    private var allDoneToday: Bool {
        guard viewOffset == 0 else { return false }
        let total = store.visibleTasks.count
        return total > 0 && store.doneCount == total
    }

    /// 全部完成庆祝：记录时刻 + 进度环脉冲 + 粒子喷发 + 轻提示音
    /// （Reduce Motion 时跳过脉冲和粒子，仅保留静态祝贺文案）
    private func celebrateAllDone() {
        celebrationAt = Date()
        celebrateToken += 1
        if store.settings.soundOn { Sound.play() }
        guard !DDMotion.reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.16)) { ringPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { ringPulse = false }
        }
    }

    /// 当前视角的任务（0 = 今天，1 = 明天）
    private var currentTasks: [TaskItem] { store.visibleTasks(offset: viewOffset) }

    private var undoneTasks: [TaskItem] {
        currentTasks.filter { !store.isDone($0, offset: viewOffset) }
    }

    private var doneTasks: [TaskItem] {
        currentTasks.filter { store.isDone($0, offset: viewOffset) }
    }

    /// 是否有定时未完成任务（“现在”线仅今天视角显示）
    private var showNowLine: Bool {
        viewOffset == 0 && undoneTasks.contains { $0.remindAt != nil }
    }

    /// “现在”线插到第一个“提醒时间晚于现在”的定时任务之前
    /// （星标置顶只影响排列，无时间任务不参与插线判断）
    private var nowLineIndex: Int {
        let undone = undoneTasks
        var index = 0
        for (i, task) in undone.enumerated() {
            guard let m = task.remindAt else { continue }
            if m > store.nowMinutes { return i }
            index = i + 1
        }
        return index
    }

    private var taskList: some View {
        let undone = undoneTasks
        let done = doneTasks
        let lineIndex = nowLineIndex
        let showLine = showNowLine
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                if currentTasks.isEmpty {
                    EmptyStateView(
                        title: viewOffset == 1 ? "明天还没有任务" : "今天还没有任务",
                        message: viewOffset == 1
                            ? "试试输入「9点 起床」快速添加\n明天的事，明天再勾"
                            : "在下方输入框添加任务\n完成后点击左侧圆圈打勾")
                }
                if allDoneToday {
                    AllDoneView(doneAt: celebrationAt)
                }
                ForEach(Array(undone.enumerated()), id: \.element.id) { idx, task in
                    if showLine && idx == lineIndex {
                        nowLine
                    }
                    taskRow(task)
                }
                if showLine && lineIndex >= undone.count {
                    nowLine
                }
                if !done.isEmpty {
                    doneHeader(doneCount: done.count, total: currentTasks.count)
                    if doneExpanded {
                        ForEach(done) { task in
                            taskRow(task)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(ddAnimation, value: lineIndex)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                }
            )
        }
        .id(viewOffset)
        .transition(.asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
        ))
    }

    private var nowLine: some View {
        NowLineView(label: store.clockString())
            .transition(.opacity)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TaskRow(task: task,
                done: store.isDone(task, offset: viewOffset),
                nowMinutes: store.nowMinutes,
                tomorrowMode: viewOffset == 1,
                onBlockedToggle: { showInfoToast("明天的事明天再说 😄") })
            .transition(DDMotion.taskRowTransition)
    }

    /// 已完成分组头：已完成 N/M，chevron 可展开/收起（默认收起）
    private func doneHeader(doneCount: Int, total: Int) -> some View {
        Button {
            withDDAnimation { doneExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(doneExpanded ? 90 : 0))
                Text("已完成 \(doneCount)/\(total)")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPointing()
        .padding(.top, 4)
    }

    // MARK: - 底部添加栏（支持自然语言快速添加 + 解析预览芯片）

    /// 是否显示解析/草稿芯片行（时间 / 时长 / 规则 任一存在即显示）
    private var showsDraftChips: Bool {
        newRemindMinutes != nil || (newDuration ?? 0) > 0 || newRule != RepeatRule()
    }

    private var addBarSection: some View {
        VStack(spacing: 6) {
            if showsDraftChips {
                draftChipRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Accent.gradient)
                TextField("添加任务…（试试「9:30 开会 45分钟」）", text: $newTitle, onEditingChanged: { editing in
                    if editing { activateApp() }
                })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($addFieldFocused)
                    .onChange(of: newTitle) { _ in syncDraftWithParse() }
                    .onSubmit(addCurrent)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(ddAnimation, value: showsDraftChips)
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

    // MARK: 解析预览芯片行

    private var draftChipRow: some View {
        HStack(spacing: 6) {
            if let m = newRemindMinutes {
                draftChip(icon: "clock.fill", text: store.timeString(m)) {
                    dismissedTimeToken = addParse?.timeToken ?? appliedTimeToken
                    newRemindMinutes = nil
                }
                .help("提醒时间 \(store.timeString(m))（来自输入解析或手动设置），点 ✗ 移除")
            }
            if let d = newDuration, d > 0 {
                draftChip(icon: "hourglass", text: "\(d) 分钟") {
                    dismissedDurationToken = addParse?.durationToken ?? appliedDurationToken
                    newDuration = nil
                }
                .help("时长 \(d) 分钟，点 ✗ 移除")
            }
            if newRule != RepeatRule() {
                draftChip(icon: ruleIcon(newRule), text: draftRuleChipText) {
                    dismissedRuleToken = addParse?.ruleToken ?? appliedRuleToken
                    withDDAnimation { newRule = RepeatRule() }
                }
                .help("重复规则 \(ruleName(newRule))，点 ✗ 恢复每天")
            }
            Spacer(minLength: 0)
        }
    }

    /// 规则芯片文案（明天的 once 显示「仅明天」）
    private var draftRuleChipText: String {
        if newRule.kind == .once, let key = store.tomorrowKey(), newRule.date == key {
            return "仅明天"
        }
        return ruleName(newRule)
    }

    private func draftChip(icon: String, text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Accent.start.opacity(0.55))
            }
            .buttonStyle(.plain)
            .hoverPointing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Accent.start.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Accent.start.opacity(0.25), lineWidth: 0.8))
        .foregroundColor(Accent.start)
    }

    /// 输入变化时重新解析：解析值作为初值回填（已手动移除/已回填过的同片段不重复回填）
    private func syncDraftWithParse() {
        let parse = parseQuickAdd(newTitle, tomorrowKey: store.tomorrowKey())
        addParse = parse
        guard parse.matched else { return }
        if let token = parse.timeToken, token != dismissedTimeToken, token != appliedTimeToken {
            newRemindMinutes = parse.remindMinutes
            appliedTimeToken = token
        }
        if let token = parse.durationToken, token != dismissedDurationToken, token != appliedDurationToken {
            newDuration = parse.duration
            appliedDurationToken = token
        }
        if let token = parse.ruleToken, token != dismissedRuleToken, token != appliedRuleToken {
            if let rule = parse.rule {
                withDDAnimation { newRule = rule }
                appliedRuleToken = token
            }
        }
    }

    private func addCurrent() {
        let raw = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // 解析出干净标题（完全无匹配时保持原文本，行为与之前一致）
        var title = raw
        if let parse = addParse, parse.matched, !parse.title.isEmpty {
            title = parse.title
        }
        let scheduledForTomorrow = newRule.kind == .once && newRule.date == store.tomorrowKey()
        // 时段冲突检测（在入列前比对既有任务；仅提示 + 黄色闪烁，不阻塞创建）
        store.detectTimeConflicts(excluding: nil, remindAt: newRemindMinutes, duration: newDuration)
        withDDAnimation {
            store.addTask(title: title, rule: newRule, remindAt: newRemindMinutes, duration: newDuration)
        }
        if scheduledForTomorrow, viewOffset == 0 {
            showInfoToast("已安排到明天 ✓ 切到「明天」看看")
        }
        newTitle = ""
        newRemindMinutes = nil
        newDuration = nil
        addParse = nil
        appliedTimeToken = nil
        appliedDurationToken = nil
        appliedRuleToken = nil
        dismissedTimeToken = nil
        dismissedDurationToken = nil
        dismissedRuleToken = nil
    }

    // MARK: 通用轻提示

    private func showInfoToast(_ message: String) {
        withDDAnimation { infoToast = message }
        infoToastToken += 1
        let token = infoToastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard infoToastToken == token else { return }
            withDDAnimation { infoToast = nil }
        }
    }

    /// 删除后的 3 秒撤销 toast（毛玻璃小条，浮在卡片底部，点“撤销”恢复）
    private func undoToastView(title: String) -> some View {
        let display = title.count > 12 ? String(title.prefix(12)) + "…" : title
        return HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("已删除「\(display)」")
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
            Button {
                withDDAnimation {
                    showUndoToast = false
                    store.undoDelete()
                }
            } label: {
                Text("撤销")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Accent.start)
            }
            .buttonStyle(.plain)
            .hoverPointing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    @EnvironmentObject var store: Store
    var title: String = "今天还没有任务"
    var message: String = "在下方输入框添加任务\n完成后点击左侧圆圈打勾"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: store.dayPeriod().icon)
                .font(.system(size: 30))
                .foregroundStyle(Accent.gradient)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.75))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - 全部完成的专属空状态（与普通空状态区分）

struct AllDoneView: View {
    let doneAt: Date?
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Accent.gradient)
                .shadow(color: Accent.start.opacity(0.35), radius: 10, y: 2)
            Text("今日全部完成！")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary.opacity(0.85))
            if let doneAt {
                Text("完成于 \(store.timeString(store.minutesFromDate(doneAt)))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text("享受当下吧 🎉")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityLabel("今日任务已全部完成")
    }
}

// MARK: - 全部完成庆祝粒子（Canvas + TimelineView，重力 + 随机初速，约 1.5s 消散）

struct ConfettiParticle {
    let angle: Double      // 初速方向（弧度）
    let speed: Double      // 初速（pt/s）
    let size: Double
    let spin: Double       // 方块自转速度
    let color: Color
    let kind: Int          // 0 圆点 1 方块

    static let gravity: Double = 320

    /// 14-20 个主题色系粒子
    static func burst() -> [ConfettiParticle] {
        let colors: [Color] = [Accent.start, Accent.end, .orange, .yellow, .pink]
        let count = Int.random(in: 14...20)
        return (0..<count).map { _ in
            ConfettiParticle(angle: Double.random(in: 0..<(Double.pi * 2)),
                             speed: Double.random(in: 40...120),
                             size: Double.random(in: 2.2...4.2),
                             spin: Double.random(in: -6...6),
                             color: colors.randomElement() ?? .orange,
                             kind: Int.random(in: 0...1))
        }
    }
}

struct CelebrationBurst: View {
    let token: Int
    @State private var particles: [ConfettiParticle] = []
    @State private var startedAt: Date? = nil
    @State private var active = false
    private let duration: Double = 1.5

    var body: some View {
        Group {
            if active {
                TimelineView(.animation) { timeline in
                    burstCanvas(now: timeline.date)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: token) { _ in start() }
    }

    private func burstCanvas(now: Date) -> some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size, now: now)
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        guard let start = startedAt else { return }
        let t = now.timeIntervalSince(start)
        guard t >= 0, t <= duration else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let fade = t / duration
        for p in particles {
            ctx.opacity = 1 - fade
            ctx.fill(particlePath(p, t: t, center: center, fade: fade), with: .color(p.color))
        }
    }

    private func particlePath(_ p: ConfettiParticle, t: Double, center: CGPoint, fade: Double) -> Path {
        let x = center.x + cos(p.angle) * p.speed * t
        let y = center.y + sin(p.angle) * p.speed * t + 0.5 * ConfettiParticle.gravity * t * t
        let radius = p.size * (1 - 0.3 * fade)
        if p.kind == 0 {
            return Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
        }
        let transform = CGAffineTransform(translationX: x, y: y).rotated(by: p.spin * t)
        let base = Path(roundedRect: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                        cornerRadius: 1)
        return base.applying(transform)
    }

    private func start() {
        guard token > 0, !DDMotion.reduceMotion else { return }
        particles = ConfettiParticle.burst()
        startedAt = Date()
        active = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            active = false
            startedAt = nil
        }
    }
}

// MARK: - 任务行

struct TaskRow: View {
    let task: TaskItem
    let done: Bool
    let nowMinutes: Int
    /// 明天视角：不允许勾选（点勾给提示）、隐藏“现在/过期/进行中”态与 streak
    var tomorrowMode: Bool = false
    var onBlockedToggle: (() -> Void)? = nil

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
        guard !tomorrowMode, !done, let s = task.remindAt, let d = task.durationMinutes else { return false }
        return nowMinutes >= s && nowMinutes < s + d
    }

    private var isOverdue: Bool {
        guard !tomorrowMode, !done, let s = task.remindAt else { return false }
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
                if tomorrowMode {
                    // 勾选仅限今天视角
                    onBlockedToggle?()
                } else {
                    withDDAnimation {
                        store.toggleDone(task.id)
                    }
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

            if task.starred && !isEditing {
                // 优先级星标：行右缘小星（右键可切换）
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.yellow)
                    .help("重要任务（右键「取消星标」可移除）")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
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
                    withDDAnimation { store.delete(task.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .hoverPointing()
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
                // 修改时间后即时做时段冲突检测（仅提示，不阻塞）
                store.detectTimeConflicts(excluding: task.id, remindAt: picked, duration: duration)
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
        let streakDays = (tomorrowMode || task.repeatRule.kind == .once) ? 0 : store.streak(of: task)
        return HStack(spacing: 6) {
            Text(task.title)
                .font(.system(size: 13.5, weight: done ? .regular : .medium))
                .strikethrough(done, color: .secondary)
                .foregroundColor(done ? .secondary : .primary)
                .lineLimit(2)
            if streakDays >= 2 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("\(streakDays)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.14)))
                .help("已连续坚持 \(streakDays) 天")
            }
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

    /// 该任务正处于冲突闪烁（Store 检测到时段重叠后持续 2 秒）
    private var timeConflictFlashing: Bool { store.timeConflictIDs.contains(task.id) }

    private var timeChipFill: Color {
        if timeConflictFlashing { return Color.yellow.opacity(0.5) }
        if inPeriod { return Color.green.opacity(0.16) }
        return isOverdue ? Color.red.opacity(0.14) : Color.secondary.opacity(0.13)
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
            Capsule().fill(timeChipFill)
        )
        // Reduce Motion 下保留静态黄色提示，避免持续闪烁造成干扰
        .animation(DDMotion.reduceMotion
                   ? .easeInOut(duration: 0.15)
                   : (timeConflictFlashing
                      ? Animation.easeInOut(duration: 0.28).repeatForever(autoreverses: true)
                      : .easeInOut(duration: 0.2)),
                   value: timeConflictFlashing)
        .foregroundColor(inPeriod ? .green : (isOverdue ? .red : .secondary))
        .hoverPointing()
        .onTapGesture { activateApp(); showTimePicker = true }
        .help(inPeriod
              ? "进行中（\(timeChipText)），点击修改"
              : (isOverdue ? "已过时段，点击修改" : "提醒时间 \(timeChipText)，点击修改"))
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            withDDAnimation { store.toggleStar(task.id) }
        } label: {
            Label(task.starred ? "取消星标" : "★ 标记重要", systemImage: task.starred ? "star.slash" : "star")
        }
        .help("星标任务置顶显示（先于时间排序）")
        if !tomorrowMode {
            Button {
                withDDAnimation { store.startFocus(task.id) }
            } label: {
                Label("开始专注 \(store.focusMinutes(for: task)) 分钟", systemImage: "play.circle")
            }
            .help("番茄钟：任务时长 \(store.focusMinutes(for: task)) 分钟（时长超过 60 分钟按 25 分钟计）")
            Divider()
        }
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
        Button(role: .destructive) { withDDAnimation { store.delete(task.id) } } label: {
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

// MARK: - 番茄钟专注条（sheetBar 下方：渐变进度 + 任务名 + 剩余时间 + 暂停/完成/取消）

struct FocusBarView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content
        }
    }

    private var remainingSeconds: Int {
        guard let session = store.focusSession else { return 0 }
        if let paused = session.pausedRemaining { return paused }
        return max(Int(session.endsAt.timeIntervalSince(Store.now())), 0)
    }

    private var content: some View {
        let remaining = remainingSeconds
        let session = store.focusSession
        let total = max(session?.totalSeconds ?? 1, 1)
        let progress = CGFloat(remaining) / CGFloat(total)
        let task = session.flatMap { store.taskByID($0.taskID) }
        return HStack(spacing: 10) {
            Image(systemName: session?.isPaused == true ? "pause.circle.fill" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Accent.gradient)
            VStack(alignment: .leading, spacing: 3) {
                Text(task?.title ?? "专注中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(Accent.gradient)
                            .frame(width: max(4, g.size.width * progress))
                    }
                }
                .frame(height: 5)
            }
            Text(Self.mmss(remaining))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.primary)
            Button {
                store.togglePauseFocus()
            } label: {
                Image(systemName: session?.isPaused == true ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Accent.start)
            }
            .buttonStyle(.plain)
            .hoverPointing()
            .help(session?.isPaused == true ? "继续专注" : "暂停专注")
            Button {
                withDDAnimation { store.completeFocus() }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .hoverPointing()
            .help("标记任务完成并结束专注")
            Button {
                withDDAnimation { store.stopFocus() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .hoverPointing()
            .help("放弃本次专注")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Accent.start.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Accent.start.opacity(0.25), lineWidth: 1)
        )
    }

    /// mm:ss 倒计时文案（迷你胶囊也复用）
    static func mmss(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
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

/// 常用 AI 供应商预设：一键填入 URL + 模型名（不动 Key）
struct AIProviderPreset: Identifiable {
    let name: String
    let url: String
    let model: String
    var id: String { url }

    static let all: [AIProviderPreset] = [
        AIProviderPreset(name: "智谱 GLM", url: "https://api.z.ai/api/paas/v4/chat/completions", model: "glm-4.6"),
        AIProviderPreset(name: "DeepSeek", url: "https://api.deepseek.com/chat/completions", model: "deepseek-chat"),
        AIProviderPreset(name: "本地 Ollama", url: "http://localhost:11434/v1/chat/completions", model: "qwen3:4b"),
    ]
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void
    @State private var loginEnabled = false
    @State private var confirmClearAll = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var showAPIKey = false
    @State private var pendingImport: AppData?
    @State private var confirmImport = false
    @State private var backupMessage: String?
    @State private var backupError = false

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    private var apiKeyBinding: Binding<String> {
        Binding(get: { store.apiKey }, set: { store.updateAPIKey($0) })
    }

    private func clipboardString() -> String {
        NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func fadeDurationLabel(_ seconds: Int) -> String {
        seconds >= 120 && seconds % 60 == 0 ? "\(seconds / 60) 分钟" : "\(seconds) 秒"
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
                    apiKey: store.apiKey,
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

    // MARK: 供应商预设芯片

    private var presetChips: some View {
        HStack(spacing: 6) {
            ForEach(AIProviderPreset.all) { preset in
                let selected = store.settings.aiBaseURL.trimmingCharacters(in: .whitespaces) == preset.url
                Button {
                    withDDAnimation {
                        store.settings.aiBaseURL = preset.url
                        store.settings.aiModel = preset.model
                    }
                } label: {
                    Text(preset.name)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(selected ? Accent.start.opacity(0.16) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(selected ? Accent.start.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                        .foregroundColor(selected ? Accent.start : Color.secondary)
                }
                .buttonStyle(.plain)
                .hoverPointing()
                .help("一键填入：\(preset.url) · \(preset.model)")
            }
            Spacer(minLength: 0)
        }
    }

    enum SettingsTab: String, CaseIterable, Hashable {
        case general = "通用"
        case ai = "AI"
        case data = "数据"
    }

    @State private var tab: SettingsTab = .general

    /// 设置内容整体可滚动，且高度不超过屏幕，杜绝“底部看不见”
    private var maxScrollHeight: CGFloat {
        min(460, (NSScreen.main?.visibleFrame.height ?? 800) - 140)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("关闭设置")
            }
            .padding(.bottom, 10)
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 12)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .general:
                        timeZoneGroup
                        windowModeGroup
                        progressGroup
                        reminderGroup
                        entryGroup
                    case .ai:
                        aiGroup
                        memoryGroup
                        reviewGroup
                    case .data:
                        maintenanceGroup
                        backupGroup
                        Text("DeskDaily v1.7 · 数据保存在本机\n~/Library/Application Support/DeskDaily/")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: maxScrollHeight)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { loginEnabled = LoginItem.isEnabled }
        .onChange(of: store.settings.tzMode) { _ in store.refreshNow() }
        .onChange(of: store.settings.windowMode) { _ in
            NotificationCenter.default.post(name: .deskDailyWindowModeChanged, object: nil)
        }
        .onChange(of: store.settings.globalHotkey) { on in
            Hotkey.setEnabled(on)
        }
        .onChange(of: store.settings.statusBarIcon) { on in
            StatusBarManager.shared.setEnabled(on)
        }
        .onChange(of: store.settings.idleFade) { on in
            WindowController.shared.idleFadeSettingChanged(on)
        }
        .onChange(of: store.settings.idleFadeSeconds) { _ in
            WindowController.shared.idleFadeSettingChanged(store.settings.idleFade)
        }
        .confirmationDialog("确定要清空「\(store.activeSheetName)」的全部任务吗？此操作不可恢复。",
                            isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("清空所有任务", role: .destructive) { withDDAnimation { store.clearAll() } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(importConfirmText, isPresented: $confirmImport, titleVisibility: .visible) {
            Button("覆盖并导入", role: .destructive) {
                if let data = pendingImport {
                    let restored = withDDAnimation { store.restoreAll(from: data) }
                    backupError = !restored
                    backupMessage = restored ? "已导入备份并生效" : (store.lastOperationError ?? "导入失败")
                }
                pendingImport = nil
                if backupMessage == "已导入备份并生效" {
                    backupError = false
                }
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        }
    }

    // MARK: 通用页分组

    private var timeZoneGroup: some View {
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
    }

    private var windowModeGroup: some View {
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
    }

    private var progressGroup: some View {
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
    }

    private var reminderGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $store.settings.notifOn) {
                    Label("系统通知提醒", systemImage: "bell")
                }
                Toggle(isOn: $store.settings.soundOn) {
                    Label("提醒音效", systemImage: "speaker.wave.2")
                }
                Text("通知横幅上可直接点「✓完成 / 推迟10分钟」，无需切回卡片。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        } label: {
            Label("提醒方式", systemImage: "alarm")
        }
    }

    private var entryGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $store.settings.globalHotkey) {
                    Label("全局热键 ⌥⇧D", systemImage: "keyboard")
                }
                Text("在任何应用里按 Option+Shift+D 都能显示 / 隐藏桌面卡片。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Toggle(isOn: $store.settings.statusBarIcon) {
                    Label("菜单栏迷你入口", systemImage: "menubar.rectangle")
                }
                Text("在系统菜单栏显示清单图标：查看 / 勾选今日任务，不必唤出卡片。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Toggle(isOn: $store.settings.idleFade) {
                        Label("闲置时自动淡化", systemImage: "circle.lefthalf.filled")
                    }
                    Spacer(minLength: 4)
                    if store.settings.idleFade {
                        Stepper(value: $store.settings.idleFadeSeconds, in: 30...600, step: 15) {
                            Text(fadeDurationLabel(store.settings.idleFadeSeconds))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Accent.start)
                        }
                        .fixedSize()
                        .help("无操作多少秒后自动淡化（30–600 秒，步进 15）")
                    }
                }
                Text("超过设定时长无悬停 / 操作时卡片自动半透明，鼠标一碰立即恢复；迷你胶囊不受影响。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Toggle(isOn: $store.settings.dockBadge) {
                    Label("Dock 图标显示未完成数", systemImage: "dock.rectangle")
                }
                Text("今日还有未完成任务时，Dock 图标角标实时显示数量，全部完成自动清空。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Divider().opacity(0.5)
                Toggle(isOn: $loginEnabled) {
                    Label("登录时自动启动", systemImage: "power")
                }
                .onChange(of: loginEnabled) { on in
                    if !LoginItem.set(on) { loginEnabled = false }
                }
            }
        } label: {
            Label("入口与启动", systemImage: "slider.horizontal.3")
        }
    }

    // MARK: AI 页分组

    private var aiGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                presetChips
                HStack(spacing: 6) {
                    TextField("接口地址（chat/completions 完整 URL）", text: $store.settings.aiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    pasteButton { store.settings.aiBaseURL = clipboardString() }
                }
                HStack(spacing: 6) {
                    Group {
                        if showAPIKey {
                            TextField("API Key（本地模型可留空）", text: apiKeyBinding)
                        } else {
                            SecureField("API Key（本地模型可留空）", text: apiKeyBinding)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .hoverPointing()
                    .help(showAPIKey ? "隐藏 Key" : "显示 Key")
                    pasteButton { store.updateAPIKey(clipboardString()) }
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
    }

    private var memoryGroup: some View {
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
                    ScrollView(showsIndicators: false) {
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
    }

    private var reviewGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: reviewEnabled) {
                    Label("AI 睡前复盘", systemImage: "moon.zzz")
                }
                if store.settings.reviewTime != nil {
                    HStack(spacing: 8) {
                        Text("复盘时间")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        reviewTimeMenus
                        Spacer(minLength: 0)
                    }
                    Text("到点发通知提醒，点「开始复盘」会打开 AI 对话并自动汇总今日完成情况。需先在本页配置好 AI 接口。")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
        } label: {
            Label("AI 睡前复盘", systemImage: "moon.zzz")
        }
    }

    // MARK: 数据页分组

    private var maintenanceGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { withDDAnimation { store.resetToday() } } label: {
                        Label("重置今日勾选", systemImage: "arrow.counterclockwise")
                    }
                    Spacer()
                    Button { confirmClearAll = true } label: {
                        Label("清空当前计划表…", systemImage: "trash")
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                Text("重置只清今天的完成状态；清空会删除当前计划表的全部任务（可用 ⌘Z 撤销）。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        } label: {
            Label("任务维护", systemImage: "checklist")
        }
    }

    private var backupGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { exportBackup() } label: {
                        Label("导出备份…", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button { importBackup() } label: {
                        Label("导入备份…", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                Text("启动时自动备份当天数据（保留最近 7 份）到 Application Support/DeskDaily/backups/")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                if let backupMessage {
                    Label(backupMessage, systemImage: backupError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(backupError ? Color.red : Color.green)
                }
            }
        } label: {
            Label("备份与恢复", systemImage: "externaldrive")
        }
    }

    // MARK: 备份 / 恢复

    // MARK: AI 睡前复盘（reviewTime nil = 关闭）

    private var reviewEnabled: Binding<Bool> {
        Binding(
            get: { store.settings.reviewTime != nil },
            set: { on in
                store.settings.reviewTime = on ? (store.settings.reviewTime ?? 22 * 60) : nil
            })
    }

    /// 紧凑版「时:分」菜单（与任务时间弹窗同款数字菜单交互）
    private var reviewTimeMenus: some View {
        let current = store.settings.reviewTime ?? 22 * 60
        return HStack(spacing: 3) {
            Menu {
                ForEach(0..<24, id: \.self) { h in
                    Button(String(format: "%02d 时", h)) {
                        store.settings.reviewTime = h * 60 + current % 60
                    }
                }
            } label: {
                Text(String(format: "%02d 时", current / 60))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 58)
            }
            .fixedSize()
            Text(":")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            Menu {
                ForEach(0..<60, id: \.self) { m in
                    Button(String(format: "%02d 分", m)) {
                        store.settings.reviewTime = (current / 60) * 60 + m
                    }
                }
            } label: {
                Text(String(format: "%02d 分", current % 60))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 58)
            }
            .fixedSize()
        }
    }

    private var backupStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = store.tz
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Store.now())
    }

    private var importConfirmText: String {
        guard let data = pendingImport else { return "确定导入备份吗？" }
        let taskCount = data.sheets.reduce(0) { $0 + $1.tasks.count }
        return "将用备份覆盖当前全部数据（备份含 \(data.sheets.count) 个计划表 / \(taskCount) 项任务），确定导入吗？"
    }

    private func exportBackup() {
        activateApp()
        guard let data = store.encodedSnapshot() else {
            backupError = true
            backupMessage = "导出失败：无法编码当前数据"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "DeskDaily-备份-\(backupStamp).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            backupError = false
            backupMessage = "已导出：\(url.lastPathComponent)"
        } catch {
            backupError = true
            backupMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importBackup() {
        activateApp()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "选择此前导出的 DeskDaily 备份 JSON 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoded = try Data(contentsOf: url)
            pendingImport = try Store.decodeAndValidate(encoded)
            confirmImport = true
        } catch {
            backupError = true
            backupMessage = "无法导入：\(error.localizedDescription)"
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
    @ObservedObject var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void
    @State private var messages: [ChatMessage] = []
    @State private var isWaiting = false
    @State private var aiStage = "正在连接模型…"
    @State private var errorMessage: String?
    @State private var detectedTasks: [AITask] = []
    @State private var selectedAIIDs: Set<UUID> = []
    @State private var showNoTasksHint = false
    @State private var confirmReplace = false

    init(session: ChatSession, onClose: @escaping () -> Void = {}) {
        self.session = session
        self.onClose = onClose
    }

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
                                Text(aiStage).font(.system(size: 11)).foregroundColor(.secondary)
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
        .onReceive(session.$draft.dropFirst()) { store.chatDraft = $0 }
        .onChange(of: messages) { latest in
                    store.chatHistory = Array(latest.suffix(40))
                }
            }
            inputBar
        }
        .frame(width: 340, height: 460)
        .onAppear(perform: autoSendPending)
        .confirmationDialog("将用 AI 候选替换当前 \(store.visibleTasks.filter { !store.isDone($0) }.count) 项未完成任务；\(store.visibleTasks.filter { store.isDone($0) }.count) 项已完成任务会保留。确定吗？",
                            isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("替换为 \(selectedAIIDs.count) 项候选任务", role: .destructive) { replaceToday() }
            Button("取消", role: .cancel) {}
        }
    }

    /// 有预填消息（复盘通知打开）时自动发送一次
    private func autoSendPending() {
        guard let message = session.pendingAutoSend, !message.isEmpty else { return }
        guard configured, !isWaiting else {
            session.draft = message
            return
        }
        session.pendingAutoSend = nil
        session.draft = message
        send()
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
                session.draft = ""
                store.chatDraft = ""
                store.chatHistory = []
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("开始新对话（长期记忆保留）")
            Button {
                onClose()
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
            // 行内 Markdown 渲染（加粗/行内代码/链接等），解析失败自动降级纯文本
            Text(markdownInline(message.content))
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
        let selected = detectedTasks.filter { selectedAIIDs.contains($0.id) }
        let completed = store.visibleTasks.filter { store.isDone($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("候选计划 · 已选 \(selected.count)/\(detectedTasks.count)", systemImage: "checklist")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Accent.gradient)
                Spacer()
                Button(selected.count == detectedTasks.count ? "全不选" : "全选") {
                    selectedAIIDs = selected.count == detectedTasks.count ? [] : Set(detectedTasks.map(\.id))
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
            Text(completed.isEmpty
                 ? "AI 只会应用你勾选的候选任务。"
                 : "当前已有 \(completed.count) 项已完成任务，整表替换不会删除它们。")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
            ForEach(detectedTasks) { task in
                let isSelected = selectedAIIDs.contains(task.id)
                Button {
                    if isSelected { selectedAIIDs.remove(task.id) } else { selectedAIIDs.insert(task.id) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? Accent.start : .secondary.opacity(0.55))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            if task.repeatDaily {
                                Text("每天重复").font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if let time = task.remindAt {
                            let end = task.durationMinutes.flatMap { duration in
                                AIClient.minutes(fromHHMM: time).map { store.timeString($0 + duration) }
                            }
                            Text(end.map { "\(time)-\($0)" } ?? time)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Accent.start.opacity(0.08) : Color.primary.opacity(0.035)))
                }
                .buttonStyle(.plain)
                .hoverPointing()
            }
            HStack(spacing: 10) {
                Button(action: applySelectedAI) {
                    Label("应用选中", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.link)
                .disabled(selected.isEmpty)
                Button(action: requestReplaceToday) {
                    Label("替换未完成项", systemImage: "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.link)
                .disabled(selected.isEmpty)
                .help("保留已完成任务，用选中候选替换当前未完成任务")
                Button(role: .destructive) {
                    detectedTasks = []
                    selectedAIIDs = []
                } label: {
                    Text("忽略").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Accent.end.opacity(0.35), lineWidth: 1))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(configured ? "告诉 AI 你今天的安排…" : "请先在设置中配置 AI 接口", text: $session.draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(send)
                .disabled(!configured || isWaiting)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        session.draft.trimmingCharacters(in: .whitespaces).isEmpty || !configured || isWaiting
                            ? AnyShapeStyle(Color.secondary.opacity(0.35))
                            : AnyShapeStyle(Accent.gradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(session.draft.trimmingCharacters(in: .whitespaces).isEmpty || !configured || isWaiting)
            .help("发送")
        }
        .padding(12)
    }

    private func send() {
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, configured, !isWaiting else { return }
        session.draft = ""
        store.chatDraft = ""
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
        aiStage = "正在连接模型…"
        errorMessage = nil
        // 新请求不能留下上一轮可点击的候选，避免误应用旧清单。
        detectedTasks = []
        showNoTasksHint = false
        let history = messages
        let system = systemPrompt
        let settings = store.settings
        Task { @MainActor in
            do {
                let reply = try await AIClient.shared.chat(system: system, messages: history, settings: settings,
                                                            apiKey: store.apiKey)
                messages.append(ChatMessage(role: "assistant", content: reply))
                aiStage = "正在解析候选任务…"
                detectedTasks = AIClient.parseTasks(from: reply)
                selectedAIIDs = Set(detectedTasks.map(\.id))
                showNoTasksHint = detectedTasks.isEmpty
                isWaiting = false
                if store.settings.memoryEnabled {
                    extractMemories()
                }
            } catch {
                detectedTasks = []
                showNoTasksHint = false
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
                apiKey: store.apiKey,
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

    private func requestReplaceToday() {
        guard !selectedAIIDs.isEmpty else {
            errorMessage = "请至少选择一项候选任务"
            return
        }
        confirmReplace = true
    }

    private func selectedAIPayload() -> [(title: String, repeatDaily: Bool, remindAt: Int?, duration: Int?)] {
        detectedTasks.filter { selectedAIIDs.contains($0.id) }.map {
            (title: $0.title,
             repeatDaily: $0.repeatDaily,
             remindAt: $0.remindAt.flatMap { AIClient.minutes(fromHHMM: $0) },
             duration: $0.durationMinutes)
        }
    }

    /// 保留今天已完成任务，用选中候选替换未完成项。
    private func replaceToday() {
        withDDAnimation {
            store.replaceUnfinished(with: selectedAIPayload(), preserveCompleted: true)
        }
        if store.lastOperationError == nil {
            detectedTasks = []
            selectedAIIDs = []
        } else {
            errorMessage = store.lastOperationError
        }
    }

    /// 应用选中候选：只追加，不改现有任务。
    private func applySelectedAI() {
        withDDAnimation {
            for task in detectedTasks where selectedAIIDs.contains(task.id) {
                let minutes = task.remindAt.flatMap { AIClient.minutes(fromHHMM: $0) }
                let rule = task.repeatDaily ? RepeatRule() : RepeatRule.once(date: store.currentDay)
                store.addTask(title: task.title, rule: rule, remindAt: minutes, duration: task.durationMinutes)
            }
        }
        if store.lastOperationError == nil {
            detectedTasks = []
            selectedAIIDs = []
        } else {
            errorMessage = store.lastOperationError
        }
    }

    /// 兼容旧入口：追加当前选中候选。
    private func appendToday() { applySelectedAI() }

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
                    .hoverPointing()
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
                        .hoverPointing()
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
