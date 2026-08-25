import AppKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 点击通知上的操作按钮（完成 / 推迟10分钟）→ 主线程路由到 Store
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let taskID = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
        if let taskID = taskID {
            DispatchQueue.main.async {
                let store = Store.shared
                if action == Notify.actionComplete {
                    withDDAnimation { store.completeTask(id: taskID) }
                } else if action == Notify.actionPostpone10 {
                    withDDAnimation { store.postponeTask(id: taskID, by: 10) }
                }
            }
        }
        // 睡前复盘：点「开始复盘」按钮或点开通知本体 → 打开 AI 复盘对话（ContentView 监听）
        if (info["open_review"] as? Bool) == true,
           action == Notify.actionStartReview || action == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .deskDailyOpenReview, object: nil)
            }
        }
        completionHandler()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        _ = Store.shared
        WindowController.shared.setup()
        Notify.requestAuth()
        Notify.registerCategories()
        Notify.center?.delegate = NotificationDelegate.shared
        // 全局热键 / 菜单栏迷你入口（按设置开关）
        Hotkey.setEnabled(Store.shared.settings.globalHotkey)
        StatusBarManager.shared.setEnabled(Store.shared.settings.statusBarIcon)
    }

    // 程序化构建主菜单（含编辑菜单），保证输入框里 ⌘X/⌘C/⌘V/⌘A 可用
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: "DeskDaily", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 DeskDaily", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let undoItem = NSMenuItem(title: "撤销删除", action: #selector(undoDeleteMenu(_:)), keyEquivalent: "z")
        undoItem.target = self
        appMenu.addItem(undoItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DeskDaily", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let taskItem = NSMenuItem(title: "任务", action: nil, keyEquivalent: "")
        let taskMenu = NSMenu(title: "任务")
        let newItem = NSMenuItem(title: "新任务", action: #selector(focusAddFieldMenu(_:)), keyEquivalent: "n")
        newItem.target = self
        taskMenu.addItem(newItem)
        taskMenu.addItem(.separator())
        let toggleItem = NSMenuItem(title: "显示 / 隐藏卡片 ⌥⇧D", action: #selector(togglePanelMenu(_:)), keyEquivalent: "")
        toggleItem.target = self
        taskMenu.addItem(toggleItem)
        taskItem.submenu = taskMenu
        mainMenu.addItem(taskItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // 点 Dock 图标 / 再次双击应用时，把面板带回到最前
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowController.shared.showPanel()
        return true
    }

    /// App 菜单「撤销删除 ⌘Z」与卡片底部 toast 的撤销走同一逻辑
    @objc private func undoDeleteMenu(_ sender: Any?) {
        withDDAnimation { Store.shared.undoDelete() }
    }

    /// 菜单「新任务 ⌘N」：唤回卡片并聚焦添加输入框（ContentView 监听）
    @objc private func focusAddFieldMenu(_ sender: Any?) {
        WindowController.shared.showPanel()
        activateApp()
        NotificationCenter.default.post(name: .deskDailyFocusAddField, object: nil)
    }

    @objc private func togglePanelMenu(_ sender: Any?) {
        WindowController.shared.togglePanel()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoDeleteMenu(_:)) {
            return Store.shared.lastDeleted != nil
        }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
