import AppKit
import Carbon.HIToolbox

/// 全局热键：⌥⇧D 在任何应用里显示/隐藏桌面卡片
/// （Carbon RegisterEventHotKey；回调统一 dispatch 到主线程再动窗口）
enum Hotkey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    /// 'DSGD'（DeskDaily Global）
    private static let signature: OSType = 0x44_53_47_44

    static func setEnabled(_ on: Bool) {
        if on { register() } else { unregister() }
    }

    private static func register() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: signature, id: 1)
        var newRef: EventHotKeyRef?
        // optionKey | shiftKey（Carbon 修饰键位掩码）
        let modifiers = UInt32(optionKey | shiftKey)
        guard RegisterEventHotKey(UInt32(kVK_ANSI_D), modifiers, id,
                                  GetApplicationEventTarget(), 0, &newRef) == noErr,
              let ref = newRef else { return }
        hotKeyRef = ref
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // @convention(c) 闭包不能捕获上下文，全部走全局单例
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotID)
            if hotID.signature == 0x44_53_47_44, hotID.id == 1 {
                // 热键事件不一定在主线程，切窗口必须回主线程
                DispatchQueue.main.async {
                    WindowController.shared.togglePanel()
                }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private static func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }
}
