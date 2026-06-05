import Foundation
import Combine

enum LLMProvider: String, CaseIterable {
    case claude
    case openAI
    case gemini
    case deepseek

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "ChatGPT"
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        }
    }

    var availableModels: [String] {
        switch self {
        case .claude:
            return [
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-opus-4-6",
                "claude-sonnet-4-5",
                "claude-opus-4-5",
                "claude-haiku-4-5",
            ]
        case .openAI:
            return [
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4o",
                "gpt-4o-mini",
                "o4-mini",
                "o3",
            ]
        case .gemini:
            return [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
            ]
        case .deepseek:
            return [
                "deepseek-v4-pro",
                "deepseek-v4-flash",
                "deepseek-chat",
                "deepseek-reasoner",
            ]
        }
    }
}

struct WeeklyGoal: Codable, Equatable {
    var text: String
    var weekLabel: String
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var provider: LLMProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") }
    }

    @Published var claudeApiKey: String {
        didSet { UserDefaults.standard.set(claudeApiKey, forKey: "claudeApiKey") }
    }

    @Published var openAIApiKey: String {
        didSet { UserDefaults.standard.set(openAIApiKey, forKey: "openAIApiKey") }
    }

    @Published var geminiApiKey: String {
        didSet { UserDefaults.standard.set(geminiApiKey, forKey: "geminiApiKey") }
    }

    @Published var deepseekApiKey: String {
        didSet { UserDefaults.standard.set(deepseekApiKey, forKey: "deepseekApiKey") }
    }

    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") }
    }

    @Published var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "geminiModel") }
    }

    @Published var deepseekModel: String {
        didSet { UserDefaults.standard.set(deepseekModel, forKey: "deepseekModel") }
    }

    // MARK: - Reminder schedule
    @Published var isReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(isReminderEnabled, forKey: "isReminderEnabled") }
    }
    @Published var reminderHour: Int {
        didSet { UserDefaults.standard.set(reminderHour, forKey: "reminderHour") }
    }
    @Published var reminderMinute: Int {
        didSet { UserDefaults.standard.set(reminderMinute, forKey: "reminderMinute") }
    }

    // MARK: - Weekly goals (multiple entries with week labels)
    @Published var weeklyGoals: [WeeklyGoal] {
        didSet { saveWeeklyGoals() }
    }

    private func saveWeeklyGoals() {
        if let data = try? JSONEncoder().encode(weeklyGoals) {
            UserDefaults.standard.set(data, forKey: "weeklyGoalsV2")
        }
    }

    func addGoal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        weeklyGoals.insert(WeeklyGoal(text: trimmed, weekLabel: Self.currentWeekRange()), at: 0)
    }

    func removeGoal(at index: Int) {
        guard weeklyGoals.indices.contains(index) else { return }
        weeklyGoals.remove(at: index)
    }

    static func currentWeekRange() -> String {
        weekRange(for: Date())
    }

    static func previousWeekRange() -> String {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return weekRange(for: lastWeek)
    }

    static func weekRange(for date: Date) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let daysToMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysToMonday, to: date)!
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: monday)) - \(fmt.string(from: friday))"
    }

    private init() {
        let defaults = UserDefaults.standard
        let savedProvider = defaults.string(forKey: "provider") ?? ""
        provider = LLMProvider(rawValue: savedProvider) ?? .claude

        claudeApiKey = defaults.string(forKey: "claudeApiKey")
            ?? defaults.string(forKey: "apiKey")
            ?? ""
        openAIApiKey = defaults.string(forKey: "openAIApiKey") ?? ""
        geminiApiKey = defaults.string(forKey: "geminiApiKey") ?? ""
        deepseekApiKey = defaults.string(forKey: "deepseekApiKey") ?? ""

        claudeModel = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-4-6"
        openAIModel = defaults.string(forKey: "openAIModel") ?? "gpt-4.1"
        geminiModel = defaults.string(forKey: "geminiModel") ?? "gemini-2.5-flash"
        deepseekModel = defaults.string(forKey: "deepseekModel") ?? "deepseek-v4-flash"

        isReminderEnabled = UserDefaults.standard.object(forKey: "isReminderEnabled") as? Bool ?? true
        reminderHour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 9
        reminderMinute = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0

        // 读取 V2 格式（带周标签），如无则迁移旧数据
        if let data = defaults.data(forKey: "weeklyGoalsV2"),
           let arr = try? JSONDecoder().decode([WeeklyGoal].self, from: data) {
            weeklyGoals = arr
        } else if let data = defaults.data(forKey: "weeklyGoalsArray"),
                  let arr = try? JSONDecoder().decode([String].self, from: data) {
            weeklyGoals = arr.map { WeeklyGoal(text: $0, weekLabel: Self.previousWeekRange()) }
        } else {
            let old = defaults.string(forKey: "weeklyGoalsText") ?? ""
            let trimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
            weeklyGoals = trimmed.isEmpty ? [] : [WeeklyGoal(text: trimmed, weekLabel: Self.previousWeekRange())]
        }

        // 一次性修复：之前迁移旧数据时错误标记了当前周
        if !defaults.bool(forKey: "wg_label_fix_1"),
           defaults.data(forKey: "weeklyGoalsArray") != nil || defaults.string(forKey: "weeklyGoalsText") != nil {
            weeklyGoals = weeklyGoals.map { WeeklyGoal(text: $0.text, weekLabel: Self.previousWeekRange()) }
            defaults.set(true, forKey: "wg_label_fix_1")
        }

        // 自动修正：如果存储的模型不在可用列表中，重置为默认值
        if !LLMProvider.claude.availableModels.contains(claudeModel) {
            claudeModel = "claude-sonnet-4-6"
        }
        if !LLMProvider.openAI.availableModels.contains(openAIModel) {
            openAIModel = "gpt-4.1"
        }
        if !LLMProvider.gemini.availableModels.contains(geminiModel) {
            geminiModel = "gemini-2.5-flash"
        }
        if !LLMProvider.deepseek.availableModels.contains(deepseekModel) {
            deepseekModel = "deepseek-v4-flash"
        }
    }

    var reminderTimeString: String {
        String(format: "%02d:%02d", reminderHour, reminderMinute)
    }

    // 构建发给 Claude 的 context
    func buildContext() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        let dateStr = formatter.string(from: Date())

        let weekday = Calendar.current.component(.weekday, from: Date())
        let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let today = weekdayNames[weekday]

        var ctx = "今天是 \(dateStr)（\(today)）。\n\n"

        let nonEmpty = weeklyGoals.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !nonEmpty.isEmpty {
            ctx += "本周目标：\n"
            for (i, goal) in nonEmpty.enumerated() {
                ctx += "\(i + 1). [\(goal.weekLabel)] \(goal.text)\n"
            }
        } else {
            ctx += "本周目标：暂未设置，请引导用户今天想做什么。\n"
        }

        return ctx
    }
}
