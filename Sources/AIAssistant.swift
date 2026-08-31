import Foundation

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct AITask: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var remindAt: String? = nil
    var repeatDaily: Bool = false
    var durationMinutes: Int? = nil

    init(title: String, remindAt: String? = nil, repeatDaily: Bool = false, durationMinutes: Int? = nil) {
        id = UUID()
        self.title = title
        self.remindAt = remindAt
        self.repeatDaily = repeatDaily
        self.durationMinutes = durationMinutes
    }

    /// 宽容解析：字段缺失、键名不同（中文/别名）、多余字段都能兜住
    init?(lenient dict: [String: Any]) {
        let lower = Dictionary(dict.map { ($0.key.lowercased(), $0.value) },
                               uniquingKeysWith: { first, _ in first })
        func pick(_ keys: [String]) -> Any? {
            for key in keys where lower[key] != nil { return lower[key] }
            return nil
        }
        guard let rawTitle = pick(["title", "task", "任务", "name", "text", "内容"]) as? String else { return nil }
        let cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "「」“”\"'_-*• "))
        guard !cleaned.isEmpty else { return nil }
        title = String(cleaned.prefix(60))
        var time: String? = nil
        if let raw = pick(["remindat", "remind_at", "time", "时间", "at"]) as? String {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil,
               AIClient.minutes(fromHHMM: s) != nil {
                time = s
            }
        }
        remindAt = time
        if let rawDuration = pick(["durationminutes", "duration_min", "duration", "时长", "minutes", "分钟数"]) {
            if let n = rawDuration as? Int {
                durationMinutes = min(max(n, 1), 600)
            } else if let s = rawDuration as? String, let n = Int(s) {
                durationMinutes = min(max(n, 1), 600)
            }
        }
        if let boolValue = pick(["repeatdaily", "repeat", "daily", "每天", "重复"]) as? Bool {
            repeatDaily = boolValue
        } else if let stringValue = pick(["repeatdaily", "repeat", "daily", "每天", "重复"]) as? String {
            repeatDaily = ["true", "每天", "是", "yes"].contains(stringValue.lowercased())
        } else {
            repeatDaily = false
        }
        id = UUID()
    }
}

enum AIError: LocalizedError {
    case badURL
    case emptyReply
    case invalidTaskPayload
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "接口地址无效，请到设置里检查"
        case .emptyReply: return "模型没有返回内容"
        case .invalidTaskPayload: return "模型返回的任务格式无法识别，请重试"
        case .http(let code, let message): return "接口错误 \(code)：\(message)"
        }
    }
}

final class AIClient {
    static let shared = AIClient()
    private init() {}

    /// OpenAI 兼容的 chat/completions 调用（智谱 GLM / DeepSeek / Ollama 等通用）
    func chat(system: String, messages: [ChatMessage], settings: AppSettings, apiKey: String, timeout: TimeInterval = 90) async throws -> String {
        let urlString = settings.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { throw AIError.badURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        struct Payload: Codable {
            let model: String
            let messages: [ChatMessage]
            let temperature: Double
        }
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = [ChatMessage(role: "system", content: system)] + messages
        request.httpBody = try JSONEncoder().encode(Payload(model: model, messages: all, temperature: 0.6))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.emptyReply }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, detail)
        }
        struct Choice: Codable {
            struct Message: Codable { let content: String? }
            let message: Message
        }
        struct Response: Codable { let choices: [Choice]? }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices?.first?.message.content, !content.isEmpty else {
            throw AIError.emptyReply
        }
        return content
    }

    /// 只保留给用户看的自然语言，隐藏模型偶尔夹带的 JSON/代码块。
    static func displayText(from text: String) -> String {
        var result = text
        if let start = result.range(of: "```json", options: [.caseInsensitive]),
           let end = result.range(of: "```", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        if let first = result.firstIndex(of: "["), let last = result.lastIndex(of: "]"), first < last {
            let candidate = String(result[first...last])
            if let data = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                result.removeSubrange(first...last)
            }
        }
        result = result.replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "我已经整理好这份安排，确认后可以生成任务候选。" : result
    }

    /// 后台专用：只返回结构化候选，不进入聊天记录。
    func generateTaskCandidates(context: [ChatMessage], settings: AppSettings, apiKey: String, timeout: TimeInterval = 60) async throws -> [AITask] {
        let system = """
        你是 DeskDaily 的结构化任务生成器。根据下面已经确认的自然语言日程，严格只输出 JSON 数组，不要输出解释、Markdown 或代码围栏。
        每项必须包含 title、remindAt（HH:mm 或 null）、repeatDaily（true/false）；可选 durationMinutes（整数分钟）。
        输出格式：[{\"title\":\"任务\",\"remindAt\":\"09:00\",\"repeatDaily\":false,\"durationMinutes\":30}]
        """
        let response = try await chat(system: system, messages: context, settings: settings, apiKey: apiKey, timeout: timeout)
        let tasks = Self.parseTasks(from: response)
        guard !tasks.isEmpty else { throw AIError.invalidTaskPayload }
        return tasks
    }

    /// 从模型回复中提取任务清单（三层兜底）：
    /// 1) ```json 代码块（宽容字段） 2) 任意 [..] / {"tasks":[..]} JSON 3) “09:00 做某事”文字日程行
    static func parseTasks(from text: String) -> [AITask] {
        var candidates: [String] = []
        if let regex = try? NSRegularExpression(pattern: "```[a-zA-Z]*\\s*([\\s\\S]*?)```", options: [.caseInsensitive]) {
            let ns = text as NSString
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            where match.numberOfRanges > 1 {
                candidates.append(ns.substring(with: match.range(at: 1)))
            }
        }
        if let first = text.firstIndex(of: "["), let last = text.lastIndex(of: "]"), first < last {
            candidates.append(String(text[first...last]))
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            candidates.append(String(text[first...last]))
        }

        var sawValidJson = false
        for candidate in candidates {
            let cleaned = candidate
                .replacingOccurrences(of: #",\s*]"#, with: "]", options: .regularExpression)
                .replacingOccurrences(of: #",\s*}"#, with: "}", options: .regularExpression)
            guard let data = cleaned.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            sawValidJson = true
            var dicts: [[String: Any]] = []
            if let array = object as? [[String: Any]] {
                dicts = array
            } else if let wrapper = object as? [String: Any] {
                for value in wrapper.values {
                    if let array = value as? [[String: Any]] { dicts += array }
                }
            }
            let tasks = dicts.compactMap { AITask(lenient: $0) }
            if !tasks.isEmpty { return tasks }
        }
        // 模型已经输出 JSON 时不再做文字行兜底（避免把 JSON 文本当日程解析）
        if sawValidJson { return [] }

        var lineTasks: [AITask] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.contains("```"),
                  let regex = try? NSRegularExpression(pattern: #"(\d{1,2}:\d{2})[\s\-—－~–至·:：.。()（）]*(.{2,40})$"#),
                  let nsLine = line as NSString? else { continue }
            guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges > 2 else { continue }
            let time = nsLine.substring(with: match.range(at: 1))
            var title = nsLine.substring(with: match.range(at: 2))
            if let leading = title.range(of: #"^\d{1,2}:\d{2}\s*[-~–—至]?\s*"#, options: .regularExpression) {
                title = String(title[leading.upperBound...])
            }
            title = title.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-—－·•:：,，.。**()（）"))
                .trimmingCharacters(in: .whitespaces)
            if AIClient.minutes(fromHHMM: time) != nil, !title.isEmpty {
                lineTasks.append(AITask(title: String(title.prefix(60)), remindAt: time, repeatDaily: false))
            }
        }
        return lineTasks.count >= 2 ? lineTasks : []
    }

    /// "HH:mm" → 当天分钟数
    static func minutes(fromHHMM text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}
