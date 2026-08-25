import AppKit
import Combine

/// 菜单栏迷你入口（NSStatusItem）：
/// 顶部当前表名 + 下一件定时任务 + 今日前 6 条（点击直接勾选）+ 显示/隐藏 + 退出
final class StatusBarManager: NSObject {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    func setEnabled(_ on: Bool) {
        if on { create() } else { remove() }
    }

    private func create() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "DeskDaily")
        statusItem = item
        rebuild()
        // 数据变化时节流刷新菜单（objectWillChange 触发频繁，1 秒一次足够）
        cancellable = Store.shared.objectWillChange
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.rebuild() }
    }

    private func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        cancellable = nil
    }

    private func rebuild() {
        guard let item = statusItem else { return }
        item.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let store = Store.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        let head = NSMenuItem(title: "DeskDaily · \(store.activeSheetName)", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)

        // 下一件定时任务（今天视角，未完成且时间最靠前的一个）
        let tasks = store.visibleTasks
        let undone = tasks.filter { !store.isDone($0) }
        let next = undone.first { ($0.remindAt ?? Int.max) >= store.nowMinutes }
            ?? undone.first { $0.remindAt != nil }
        let nextTitle: String
        if let next, let minutes = next.remindAt {
            nextTitle = "⏱ 下一件 \(store.timeString(minutes)) \(clip(next.title))"
        } else {
            nextTitle = "今天没有定时任务"
        }
        let nextItem = NSMenuItem(title: nextTitle, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)
        menu.addItem(.separator())

        // 今日前 6 条（当前表），✓/○ 可点击直接勾选
        for task in tasks.prefix(6) {
            let mark = store.isDone(task) ? "✓" : "○"
            let time = task.remindAt.map { " \(store.timeString($0))" } ?? ""
            let item = NSMenuItem(title: "\(mark)\(time) \(clip(task.title))",
                                  action: #selector(toggleTask(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = task.id
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "显示 / 隐藏卡片", action: #selector(togglePanelAction(_:)), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: "退出 DeskDaily", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func clip(_ text: String) -> String {
        text.count > 16 ? String(text.prefix(16)) + "…" : text
    }

    // MARK: 动作

    @objc private func toggleTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        Store.shared.toggleDone(id)
        rebuild()
    }

    @objc private func togglePanelAction(_ sender: NSMenuItem) {
        WindowController.shared.togglePanel()
    }
}
