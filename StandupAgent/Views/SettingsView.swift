import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var apiKeyVisible = false
    @State private var newGoalText: String = ""
    @State private var reminderTime: Date = {
        let s = AppSettings.shared
        var c = Calendar.current.dateComponents([.year,.month,.day], from: Date())
        c.hour = s.reminderHour
        c.minute = s.reminderMinute
        return Calendar.current.date(from: c) ?? Date()
    }()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gear") }
            goalsTab
                .tabItem { Label("本周目标", systemImage: "checklist") }
        }
        .padding(20)
        .frame(width: 540)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker("接口", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    if apiKeyVisible {
                        TextField(apiKeyPlaceholder, text: selectedApiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(apiKeyPlaceholder, text: selectedApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { apiKeyVisible.toggle() }) {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Picker("模型", selection: selectedModel) {
                    ForEach(settings.provider.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Text(providerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("模型接口")
                    .font(.headline)
            }

            Divider().padding(.vertical, 8)

            // Reminder schedule
            Section {
                Toggle("启用早会提醒", isOn: $settings.isReminderEnabled)
                    .onChange(of: settings.isReminderEnabled) { _ in
                        reschedule()
                    }

                if settings.isReminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: reminderTime) { newVal in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                        settings.reminderHour = c.hour ?? 9
                        settings.reminderMinute = c.minute ?? 0
                        reschedule()
                    }

                    Text("仅工作日（周一至周五）提醒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("提醒设置")
                    .font(.headline)
            }

            Spacer()
        }
        .formStyle(.grouped)
    }

    private var selectedApiKey: Binding<String> {
        switch settings.provider {
        case .claude: return $settings.claudeApiKey
        case .openAI: return $settings.openAIApiKey
        case .gemini: return $settings.geminiApiKey
        case .deepseek: return $settings.deepseekApiKey
        }
    }

    private var selectedModel: Binding<String> {
        switch settings.provider {
        case .claude: return $settings.claudeModel
        case .openAI: return $settings.openAIModel
        case .gemini: return $settings.geminiModel
        case .deepseek: return $settings.deepseekModel
        }
    }

    private var apiKeyPlaceholder: String {
        switch settings.provider {
        case .claude: return "Claude API Key"
        case .openAI: return "OpenAI API Key"
        case .gemini: return "Gemini API Key"
        case .deepseek: return "DeepSeek API Key"
        }
    }

    private var providerHint: String {
        switch settings.provider {
        case .claude: return "在 console.anthropic.com 生成 Claude API Key"
        case .openAI: return "在 platform.openai.com 生成 OpenAI API Key"
        case .gemini: return "在 ai.google.dev 获取 Gemini API Key"
        case .deepseek: return "在 platform.deepseek.com 生成 DeepSeek API Key"
        }
    }

    // MARK: - Goals Tab

    private var goalsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本周目标")
                .font(.headline)

            Text("早会时会基于这些目标引导你")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 添加新目标（大输入框）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppSettings.currentWeekRange())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { commitNewGoal() }) {
                        Label("添加目标", systemImage: "plus.circle.fill")
                    }
                    .disabled(newGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextEditor(text: $newGoalText)
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.4))
                    )
            }

            // 已有目标列表
            if settings.weeklyGoals.isEmpty {
                Text("暂无目标，在上方添加")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(settings.weeklyGoals.enumerated()), id: \.offset) { index, _ in
                            goalRow(index: index)
                        }
                    }
                }
            }
        }
    }

    private func goalRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(settings.weeklyGoals[index].weekLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { settings.removeGoal(at: index) }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $settings.weeklyGoals[index].text)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 60)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )
        }
    }

    private func commitNewGoal() {
        settings.addGoal(newGoalText)
        newGoalText = ""
    }

    // MARK: - Helpers

    private func reschedule() {
        // 通知 AppDelegate 重新调度
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.scheduleNextReminder()
        }
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
