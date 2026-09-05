import AppKit
import SwiftUI
import CoreGraphics

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class WindowController: NSObject, NSWindowDelegate {
    static let shared = WindowController()
    private var panel: WidgetPanel?
    private var aiPanel: WidgetPanel?
    private var settingsPanel: WidgetPanel?
    let chatSession = ChatSession()
    private var isAnimatingFit = false
    private var fitTargetHeight: CGFloat = 0

    // MARK: 折叠（迷你胶囊）

    /// 折叠态：内容切迷你胶囊、窗口固定小尺寸、fitHeight 跳过、闲置不淡化
    private(set) var isCollapsed = false
    static let miniSize = NSSize(width: 244, height: 56)
    /// 折叠前的完整窗口 frame（展开时恢复宽度；折叠期间的持久化位置也基于它）
    private var expandedFrame: NSRect? = nil
    /// 最近一次内容自适应高度（展开时恢复高度用）
    private var lastContentHeight: CGFloat = 0

    // MARK: 边缘磁吸 / 形态动画

    /// 磁吸或折叠/展开动画进行中：抑制重复回调与中途存档
    private var isSnapping = false

    // MARK: 闲置淡化

    private var idleTimer: Timer? = nil
    private var cardHovered = false
    private var faded = false
    private static let idleFadeSeconds: TimeInterval = 90
    private static let fadedAlpha: CGFloat = 0.55

    func setup() {
        guard panel == nil else { return }
        let store = Store.shared
        var frame = store.settings.windowFrame ?? Self.defaultFrame()
        if !NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
            frame = Self.defaultFrame()
        }
        let p = WidgetPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        p.isReleasedWhenClosed = false
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = true
        p.level = Self.level(for: store.settings.windowMode)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 320, height: 260)
        for button in [p.standardWindowButton(.closeButton),
                       p.standardWindowButton(.miniaturizeButton),
                       p.standardWindowButton(.zoomButton)].compactMap({ $0 }) {
            button.isHidden = true
        }
        p.contentView = NSHostingView(rootView: ContentView().environmentObject(store))
        p.delegate = self
        if store.settings.collapsed {
            // 上次退出时是迷你胶囊：重启直接保持折叠态（顶边不动收成小尺寸）
            isCollapsed = true
            expandedFrame = frame
            lastContentHeight = frame.height
            p.minSize = Self.miniSize
            frame.origin.y = frame.maxY - Self.miniSize.height
            frame.size = Self.miniSize
            p.setFrame(frame, display: true)
        }
        p.orderFrontRegardless()
        panel = p
        scheduleIdleFade()

        NotificationCenter.default.addObserver(
            forName: .deskDailyWindowModeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyWindowMode()
        }
    }

    // MARK: - 常驻辅助面板（AI / 设置）

    private func makeAuxiliaryPanel(frame: NSRect) -> WidgetPanel {
        let p = WidgetPanel(contentRect: frame,
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        p.isReleasedWhenClosed = false
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        // 辅助窗口必须有自己的不透明底：不能复用主卡片的透明桌面材质，
        // 否则主卡片和桌面会透进 AI 内容，形成重影。
        p.isOpaque = true
        p.backgroundColor = .windowBackgroundColor
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.isMovableByWindowBackground = true
        p.level = Self.level(for: Store.shared.settings.windowMode)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.delegate = self
        return p
    }

    private func auxiliaryFrame(width: CGFloat, height: CGFloat) -> NSRect {
        guard let main = panel else { return NSRect(x: 160, y: 160, width: width, height: height) }
        let screen = main.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = main.frame.maxX + 12
        if x + width > visible.maxX { x = main.frame.minX - width - 12 }
        if x < visible.minX { x = max(visible.minX + 12, main.frame.midX - width / 2) }
        let y = min(max(main.frame.maxY - height, visible.minY + 12), visible.maxY - height - 12)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func showAIPanel(autoSend: String? = nil) {
        setup()
        let store = Store.shared
        if chatSession.draft.isEmpty { chatSession.draft = store.chatDraft }
        if let autoSend, !autoSend.isEmpty { chatSession.pendingAutoSend = autoSend }
        let p: WidgetPanel
        if let existing = aiPanel {
            p = existing
        } else {
            p = makeAuxiliaryPanel(frame: auxiliaryFrame(width: 360, height: 500))
            p.contentView = NSHostingView(rootView: ChatView(session: chatSession, onClose: { [weak self] in
                self?.hideAIPanel()
            }).environmentObject(store))
            aiPanel = p
        }
        p.level = Self.level(for: store.settings.windowMode)
        p.orderFrontRegardless()
        activateApp()
        p.makeKey()
    }

    func hideAIPanel() {
        storeChatDraft()
        aiPanel?.orderOut(nil)
    }

    func showSettingsPanel() {
        setup()
        let store = Store.shared
        let p: WidgetPanel
        if let existing = settingsPanel {
            p = existing
        } else {
            p = makeAuxiliaryPanel(frame: auxiliaryFrame(width: 330, height: 520))
            p.contentView = NSHostingView(rootView: SettingsView(onClose: { [weak self] in
                self?.hideSettingsPanel()
            }).environmentObject(store))
            settingsPanel = p
        }
        p.level = Self.level(for: store.settings.windowMode)
        p.orderFrontRegardless()
        activateApp()
        p.makeKey()
    }

    func hideSettingsPanel() { settingsPanel?.orderOut(nil) }

    private func storeChatDraft() {
        let draft = chatSession.draft.trimmingCharacters(in: CharacterSet.newlines)
        if Store.shared.chatDraft != draft { Store.shared.chatDraft = draft }
    }

    /// Dock 图标点击 / 重新打开应用时调用
    func showPanel() {
        guard let p = panel else { return }
        unfade()  // 点 Dock 图标也是交互，立即恢复不透明
        p.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 全局热键 ⌥⇧D / 菜单栏：切换卡片显隐（淡入淡出，不抢前台焦点）
    func togglePanel() {
        guard let p = panel else { return }
        if p.isVisible {
            if DDMotion.reduceMotion {
                p.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    p.animator().alphaValue = 0
                }, completionHandler: {
                    p.orderOut(nil)
                    p.alphaValue = 1
                })
            }
        } else {
            faded = false
            p.orderFrontRegardless()
            if DDMotion.reduceMotion {
                p.alphaValue = 1
            } else {
                p.alphaValue = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    p.animator().alphaValue = 1
                })
            }
        }
    }

    static func level(for mode: WindowMode) -> NSWindow.Level {
        switch mode {
        case .desktop:
            // 必须高于 Finder 的全屏桌面图标窗口才能收到点击；
            // 仍远低于普通窗口（层级 0），不影响“只在桌面可见”的效果
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            return .floating
        }
    }

    static func defaultFrame() -> CGRect {
        let w: CGFloat = 340
        let h: CGFloat = 560
        guard let screen = NSScreen.main else { return CGRect(x: 120, y: 120, width: w, height: h) }
        let vis = screen.visibleFrame
        return CGRect(x: vis.maxX - w - 24, y: vis.maxY - h - 16, width: w, height: h)
    }

    // MARK: - 折叠 / 展开（迷你胶囊）

    /// 切换窗口形态：内容切换由 ContentView 负责，这里管窗口尺寸（顶边不动，带动画）
    func setCollapsed(_ collapsed: Bool) {
        guard let p = panel, collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        unfade()  // 形态切换时恢复不透明
        isSnapping = true  // 形态动画期间抑制磁吸与中途存档
        if collapsed {
            expandedFrame = p.frame
            p.minSize = Self.miniSize
            var f = p.frame
            f.origin.y = f.maxY - Self.miniSize.height
            f.size = Self.miniSize
            animateSetFrame(f, duration: 0.32) { [weak self] in
                self?.isSnapping = false
                self?.saveFrame()
            }
        } else {
            let restored = expandedFrame ?? p.frame
            p.minSize = NSSize(width: 320, height: 260)
            let vis = (p.screen ?? NSScreen.main)?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            var h = lastContentHeight > 0 ? lastContentHeight : restored.height
            h = min(max(h, 260), vis.height * 0.82)
            var f = p.frame
            f.size = NSSize(width: max(restored.width, 320), height: h)
            f.origin.y = f.maxY - f.height
            animateSetFrame(f, duration: 0.32) { [weak self] in
                self?.isSnapping = false
                self?.saveFrame()
            }
        }
    }

    /// 通用窗口 frame 动画（Reduce Motion 时直接落位）
    private func animateSetFrame(_ f: NSRect, duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let p = panel else { return }
        if DDMotion.reduceMotion {
            p.setFrame(f, display: false)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(f, display: false)
        }, completionHandler: completion)
    }

    /// 按内容自适应窗口高度（顶边不动，封顶为屏幕高度的 82%；带平滑动画）；折叠态跳过
    func fitHeight(to contentHeight: CGFloat) {
        guard !isCollapsed, let p = panel else { return }
        let vis = (p.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let newH = min(max(contentHeight, 280), vis.height * 0.82)
        lastContentHeight = newH
        // 动画进行中且目标一致：忽略重复的高度回调，避免反复重启动画
        if isAnimatingFit, abs(fitTargetHeight - newH) <= 1 { return }
        fitTargetHeight = newH
        var f = p.frame
        guard abs(f.height - newH) > 0.6 else { return }
        f.origin.y = f.maxY - newH
        f.size.height = newH
        if DDMotion.reduceMotion {
            p.setFrame(f, display: false)
            saveFrame()
            return
        }
        isAnimatingFit = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(f, display: false)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isAnimatingFit = false
            self.saveFrame()
        })
    }

    private func applyWindowMode() {
        guard let p = panel else { return }
        let new = Self.level(for: Store.shared.settings.windowMode)
        guard p.level != new else { return }
        p.orderOut(nil)
        p.level = new
        p.orderFrontRegardless()
        aiPanel?.level = new
        settingsPanel?.level = new
    }

    // MARK: - 屏幕边缘磁吸

    /// 拖动结束后距屏幕可见区域任一边缘 <24pt → 0.18s 吸附贴边（留 8pt 缝隙）
    private func snapToScreenEdgeIfNeeded() {
        guard let p = panel, !isAnimatingFit, !isSnapping else { return }
        guard let screen = p.screen ?? NSScreen.main else { return }
        let vis = screen.visibleFrame
        let f = p.frame
        let threshold: CGFloat = 24
        let margin: CGFloat = 8
        var target = f
        var snapped = false
        if abs(f.minX - vis.minX) < threshold { target.origin.x = vis.minX + margin; snapped = true }
        if abs(vis.maxX - f.maxX) < threshold { target.origin.x = vis.maxX - margin - f.width; snapped = true }
        if abs(vis.maxY - f.maxY) < threshold { target.origin.y = vis.maxY - margin - f.height; snapped = true }
        if abs(f.minY - vis.minY) < threshold { target.origin.y = vis.minY + margin; snapped = true }
        guard snapped, target != f else { return }
        isSnapping = true
        if DDMotion.reduceMotion {
            p.setFrame(target, display: false)
            isSnapping = false
            saveFrame()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(target, display: false)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isSnapping = false
            self.saveFrame()
        })
    }

    // MARK: - 闲置自动淡化

    /// ContentView 整卡 onHover 回调：悬停立即恢复不透明并重置闲置计时
    func noteCardHover(_ inside: Bool) {
        cardHovered = inside
        if inside { unfade() }
        scheduleIdleFade()
    }

    /// 设置里开/关「闲置时自动淡化」
    func idleFadeSettingChanged(_ on: Bool) {
        if on {
            scheduleIdleFade()
        } else {
            idleTimer?.invalidate()
            idleTimer = nil
            unfade()
        }
    }

    private func scheduleIdleFade() {
        idleTimer?.invalidate()
        let seconds = max(30, Store.shared.settings.idleFadeSeconds)
        let timer = Timer(timeInterval: TimeInterval(seconds), target: self,
                          selector: #selector(idleFadeFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    @objc private func idleFadeFired() {
        idleTimer = nil
        guard let p = panel, p.isVisible, !cardHovered, !isCollapsed, !faded,
              Store.shared.settings.idleFade else { return }
        faded = true
        if DDMotion.reduceMotion {
            p.alphaValue = Self.fadedAlpha
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            p.animator().alphaValue = Self.fadedAlpha
        })
    }

    /// 恢复不透明（悬停 / 形态切换 / 点 Dock 图标 / 关闭设置时调用）
    func unfade() {
        guard faded, let p = panel else { return }
        faded = false
        if DDMotion.reduceMotion {
            p.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        })
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == aiPanel {
            hideAIPanel()
            return false
        }
        if sender == settingsPanel {
            hideSettingsPanel()
            return false
        }
        return true
    }

    // 高度自适应 / 磁吸 / 形态动画期间不逐帧保存 frame，动画结束时统一保存
    func windowDidMove(_ notification: Notification) {
        if !isAnimatingFit && !isSnapping { saveFrame() }
        snapToScreenEdgeIfNeeded()
    }
    func windowDidResize(_ notification: Notification) {
        if !isAnimatingFit && !isSnapping { saveFrame() }
    }

    private func saveFrame() {
        guard let p = panel else { return }
        if isCollapsed, let exp = expandedFrame {
            // 折叠期间保存“展开后应恢复”的 frame：尺寸取折叠前，位置取当前顶边
            var f = exp
            f.origin.y = p.frame.maxY - f.height
            Store.shared.settings.windowFrame = f
        } else if !isCollapsed {
            Store.shared.settings.windowFrame = p.frame
        }
    }
}
