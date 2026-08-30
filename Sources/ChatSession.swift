import Foundation
import Combine

/// AI 面板的跨视图运行期状态。WindowController 强持有它，
/// 所以切换桌面、隐藏或重新显示 AI 面板时不会丢失草稿和在途状态。
final class ChatSession: ObservableObject {
    @Published var draft: String
    @Published var pendingAutoSend: String?

    init(draft: String = "") {
        self.draft = draft
    }

    func resetRuntimeState() {
        pendingAutoSend = nil
    }
}
