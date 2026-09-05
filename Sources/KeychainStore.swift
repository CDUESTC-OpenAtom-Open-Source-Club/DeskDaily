import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()
    static let service = "local.blackevil.deskdaily.ai"
    static let account = "api-key"

    private init() {}

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    func migrateLegacyValue(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if try read()?.isEmpty != false { try save(value) }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let status): return "无法访问 macOS 钥匙串（错误码 \(status)）"
        case .invalidData: return "钥匙串中的 API Key 数据无效"
        }
    }
}

struct AppDataValidator {
    static let currentSchemaVersion = 2
    private static let dayPattern = #"^\d{4}-\d{2}-\d{2}$"#
    private static let colorPattern = #"^[0-9A-Fa-f]{6}$"#

    static func validate(_ data: AppData) throws -> AppData {
        guard data.schemaVersion <= currentSchemaVersion else {
            throw DataValidationError.futureSchema(data.schemaVersion)
        }
        var normalized = data
        if let active = data.activeSheetId,
           !data.sheets.contains(where: { $0.id == active }) {
            normalized.activeSheetId = data.sheets.first?.id
        } else if data.activeSheetId == nil {
            normalized.activeSheetId = data.sheets.first?.id
        }
        var sheetIDs = Set<UUID>()
        var taskIDs = Set<UUID>()
        for sheet in data.sheets {
            try validateSheet(sheet, sheetIDs: &sheetIDs, taskIDs: &taskIDs)
        }
        for template in data.templates {
            try validateSheet(template, sheetIDs: &sheetIDs, taskIDs: &taskIDs)
        }
        return normalized
    }

    private static func validateSheet(_ sheet: PlanSheet, sheetIDs: inout Set<UUID>, taskIDs: inout Set<UUID>) throws {
        guard sheet.id != UUID(), sheetIDs.insert(sheet.id).inserted else {
            throw DataValidationError.invalidSheet(sheet.id.uuidString, reason: "计划表 UUID 为空或重复")
        }
        let name = sheet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 16 else {
            throw DataValidationError.invalidSheet(sheet.id.uuidString, reason: "计划表名称不能为空且不能超过 16 个字符")
        }
        guard sheet.colorHex.range(of: colorPattern, options: .regularExpression) != nil else {
            throw DataValidationError.invalidSheet(sheet.id.uuidString, reason: "主题色必须是 6 位十六进制颜色")
        }
        for task in sheet.tasks {
            guard task.id != UUID(), taskIDs.insert(task.id).inserted else {
                throw DataValidationError.invalidTask(task.id.uuidString, reason: "任务 UUID 为空或重复")
            }
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  task.title.count <= 60 else {
                throw DataValidationError.invalidTask(task.id.uuidString, reason: "任务标题不能为空且不能超过 60 个字符")
            }
            try TaskItem.validate(remindAt: task.remindAt, duration: task.durationMinutes)
            switch task.repeatRule.kind {
            case .daily: break
            case .weekly:
                guard !task.repeatRule.weekdays.isEmpty,
                      task.repeatRule.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                    throw DataValidationError.invalidTask(task.id.uuidString, reason: "每周规则必须选择 1 至 7 且至少一天")
                }
            case .once:
                guard task.repeatRule.date.range(of: dayPattern, options: .regularExpression) != nil,
                      validDay(task.repeatRule.date) else {
                    throw DataValidationError.invalidTask(task.id.uuidString, reason: "一次性日期必须是有效的 yyyy-MM-dd")
                }
            }
        }
    }

    private static func validDay(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }
}

enum DataValidationError: LocalizedError {
    case futureSchema(Int)
    case invalidSheet(String, reason: String)
    case invalidTask(String, reason: String)
    case invalidTime(String)

    var errorDescription: String? {
        switch self {
        case .futureSchema(let version): return "数据版本 \(version) 高于当前支持版本，未加载该文件"
        case .invalidSheet(let id, let reason): return "计划表 \(id)：\(reason)"
        case .invalidTask(let id, let reason): return "任务 \(id)：\(reason)"
        case .invalidTime(let reason): return reason
        }
    }
}

extension TaskItem {
    static func validate(remindAt: Int?, duration: Int?) throws {
        if let start = remindAt, !(0...1439).contains(start) {
            throw DataValidationError.invalidTime("提醒时间必须在 00:00 至 23:59 之间")
        }
        if let duration {
            guard (1...600).contains(duration) else {
                throw DataValidationError.invalidTime("时段时长必须在 1 至 600 分钟之间")
            }
            if let start = remindAt, start + duration >= 1440 {
                throw DataValidationError.invalidTime("时段不能跨午夜，请缩短时长或调整开始时间")
            }
        }
    }
}

// MARK: - 纯统计口径（不依赖 Store 实例，可独立测试）

enum StatsCore {
    /// 统计口径的“该天活跃”：重复规则命中，且该天不早于任务创建日
    static func wasActive(_ task: TaskItem, onDay key: String, weekday: Int) -> Bool {
        guard task.repeatRule.isActive(on: key, weekday: weekday) else { return false }
        return task.createdOn.isEmpty || task.createdOn <= key
    }

    /// 某天跨给定计划表的活跃任务数 / 已完成数
    static func dayCounts(sheets: [PlanSheet], dayKey: String, weekday: Int) -> (total: Int, done: Int) {
        var total = 0
        var done = 0
        for sheet in sheets {
            for task in sheet.tasks {
                guard wasActive(task, onDay: dayKey, weekday: weekday) else { continue }
                total += 1
                if task.doneDays.contains(dayKey) { done += 1 }
            }
        }
        return (total, done)
    }

    /// 单表口径（统计页“当前计划表”范围用）
    static func dayCounts(sheet: PlanSheet?, dayKey: String, weekday: Int) -> (total: Int, done: Int) {
        guard let sheet else { return (0, 0) }
        return dayCounts(sheets: [sheet], dayKey: dayKey, weekday: weekday)
    }
}
