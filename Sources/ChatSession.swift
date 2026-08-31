import Foundation
import Combine

/// AI 面板的跨视图运行期状态。WindowController 强持有它，
/// 所以切换桌面、隐藏或重新显示 AI 面板时不会丢失草稿和候选计划。
final class ChatSession: ObservableObject {
    enum CandidatePhase: Equatable {
        case idle
        case generating
        case ready
        case failed(String)
    }

    @Published var draft: String
    @Published var pendingAutoSend: String?
    @Published var candidateTasks: [AITask] = []
    @Published var selectedCandidateIDs: Set<UUID> = []
    @Published var candidatePhase: CandidatePhase = .idle

    private(set) var candidateRequestID: UUID?
    private var candidateTask: Task<Void, Never>?

    init(draft: String = "") {
        self.draft = draft
    }

    var hasCandidates: Bool { !candidateTasks.isEmpty }
    var isGeneratingCandidates: Bool { candidatePhase == .generating }

    func startCandidateGeneration(context: [ChatMessage], settings: AppSettings, apiKey: String,
                                   onComplete: @escaping ([AITask]) -> Void) {
        candidateTask?.cancel()
        let requestID = UUID()
        candidateRequestID = requestID
        candidatePhase = .generating
        candidateTasks = []
        selectedCandidateIDs = []
        // 强捕获 self：会话由 WindowController 常驻持有，请求最长 60s，
        // 完成时主动清空 candidateTask 打破引用链
        candidateTask = Task {
            do {
                let tasks = try await AIClient.shared.generateTaskCandidates(
                    context: context, settings: settings, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.candidateRequestID == requestID else { return }
                    self.candidateTask = nil
                    self.candidateTasks = tasks
                    self.selectedCandidateIDs = Set(tasks.map(\.id))
                    self.candidatePhase = .ready
                    onComplete(tasks)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.candidateRequestID == requestID else { return }
                    self.candidateTask = nil
                    self.candidateTasks = []
                    self.selectedCandidateIDs = []
                    self.candidatePhase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelCandidateGeneration() {
        candidateTask?.cancel()
        candidateTask = nil
        candidateRequestID = nil
        candidatePhase = .idle
        candidateTasks = []
        selectedCandidateIDs = []
    }

    func clearCandidatePlan() {
        candidateTask?.cancel()
        candidateTask = nil
        candidateRequestID = nil
        candidatePhase = .idle
        candidateTasks = []
        selectedCandidateIDs = []
    }

    func resetRuntimeState() {
        pendingAutoSend = nil
        clearCandidatePlan()
    }
}
