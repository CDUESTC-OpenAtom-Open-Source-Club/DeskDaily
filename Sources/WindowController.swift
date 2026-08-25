import AppKit
import SwiftUI
import CoreGraphics

extension Notification.Name {
    static let deskDailyWindowModeChanged = Notification.Name("DeskDailyWindowModeChanged")
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class WindowController: NSObject, NSWindowDelegate {
    static let shared = WindowController()
    private var panel: WidgetPanel?

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
        p.orderFrontRegardless()
        panel = p

        NotificationCenter.default.addObserver(
            forName: .deskDailyWindowModeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyWindowMode()
        }
    }

    /// Dock 图标点击 / 重新打开应用时调用
    func showPanel() {
        guard let p = panel else { return }
        p.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
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

    /// 按内容自适应窗口高度（顶边不动，封顶为屏幕高度的 82%）
    func fitHeight(to contentHeight: CGFloat) {
        guard let p = panel else { return }
        let vis = (p.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let newH = min(max(contentHeight, 280), vis.height * 0.82)
        var f = p.frame
        guard abs(f.height - newH) > 0.6 else { return }
        f.origin.y = f.maxY - newH
        f.size.height = newH
        p.setFrame(f, display: false)
    }

    private func applyWindowMode() {
        guard let p = panel else { return }
        let new = Self.level(for: Store.shared.settings.windowMode)
        guard p.level != new else { return }
        p.orderOut(nil)
        p.level = new
        p.orderFrontRegardless()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard let p = panel else { return }
        Store.shared.settings.windowFrame = p.frame
    }
}
