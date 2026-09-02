import AppKit
import SwiftUI

/// 演示模式自动截图：`DD_EXPORT_SHOTS=1` 时，应用用真实界面代码 + 演示数据
/// 离屏渲染出 PNG（README 展示用）。不是手绘 mockup——就是应用自己的视图。
enum ShotExporter {
    static func exportAll() {
        let store = Store.shared
        store.settings.onboardingDone = true          // 导出态跳过首启引导
        store.backfillDemoHistory()                    // 给演示任务回填约 5 周历史，热力图/连胜有真实形状

        // AI 对话示例（自然语言两阶段流程的第一阶段）
        if store.chatHistory.isEmpty {
            store.chatHistory = [                ChatMessage(role: "user", content: "明天要交课程作业，今天晚上还想去健身。帮我安排一下今天吧，白天我有大块时间。"),
                ChatMessage(role: "assistant", content: """
好的，结合你白天有空、晚上要健身，建议这样安排：

- 09:30 晨间站会，15 分钟同步进度
- 10:30 产品评审，45 分钟，重点过桌面清单 v2.3
- 14:00 专注写课程作业，90 分钟，赶明早截止
- 16:30 回复合作邮件，30 分钟收尾
- 18:00 健身房力量训练，60 分钟
- 22:00 睡前阅读 20 分钟

这份安排可以吗？确认后我可以帮你生成任务清单。
""")
            ]
        }

        let dir = shotsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 演示 AI 配置（仅写入一次性导出数据目录）：去掉「未配置」徽章，展示真实使用状态
        if store.settings.aiBaseURL.isEmpty {
            store.settings.aiBaseURL = "https://api.z.ai/api/paas/v4/chat/completions"
            store.settings.aiModel = "glm-4.6"
        }

        // 前两项演示任务标记为今天已完成（截图展示勾选态与进度环）；
        // 配合启动参数 DD_TIME_SHIFT_MINUTES≈640 使"专注开发"处于 14:00-15:30 的进行中绿色状态
        for task in store.visibleTasks.prefix(2) {
            if !store.isDone(task) { store.toggleDone(task.id) }
        }

        // 1. 主卡片
        render(name: "overview-main", size: NSSize(width: 340, height: 580), dir: dir) {
            ContentView()
        }

        // 2. 专注模式（主卡片 + 顶部专注条）
        if let task = store.visibleTasks.first(where: { !store.isDone($0) }) ?? store.visibleTasks.first {
            store.focusSession = FocusSession(taskID: task.id,
                                              endsAt: Store.now().addingTimeInterval(15 * 60),
                                              totalSeconds: 15 * 60, pausedRemaining: nil)
        }
        render(name: "focus-mode", size: NSSize(width: 340, height: 620), dir: dir) {
            ContentView()
        }
        store.focusSession = nil

        // 3. AI 对话
        render(name: "ai-planner", size: NSSize(width: 340, height: 460), dir: dir) {
            ChatView(session: WindowController.shared.chatSession, onClose: {})
        }

        // 4. 统计页（自身无背景填充，垫窗口底色避免透明）
        render(name: "statistics-heatmap", size: NSSize(width: 380, height: 420), dir: dir) {
            statisticsWithBackground
        }

        // 5. 模板目录
        render(name: "template-catalog", size: NSSize(width: 390, height: 520), dir: dir) {
            catalogWithBackground
        }

        NSLog("ShotExporter 已导出到 \(dir.path)")
    }

    private static func shotsDirectory() -> URL {
        if let dir = ProcessInfo.processInfo.environment["DD_SHOTS_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private static var statisticsWithBackground: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            StatisticsView()
        }
    }

    private static var catalogWithBackground: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            TemplateCatalogView()
        }
    }

    /// 离屏渲染视图为 2x PNG（自动注入 Store 环境对象）
    private static func render<V: View>(name: String, size: NSSize, dir: URL, @ViewBuilder view: () -> V) {
        let hosting = NSHostingView(rootView: view().environmentObject(Store.shared))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        hosting.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        } catch {
            NSLog("ShotExporter 写入 \(name) 失败：\(error)")
        }
    }
}
