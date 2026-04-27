import SwiftUI
import SwiftData
import UserNotifications

extension Notification.Name {
    static let standupSessionCompleted = Notification.Name("standupSessionCompleted")
}

@main
struct StandupAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 无主窗口，完全由 AppDelegate 控制
        Settings {
            EmptyView()
        }
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StandupSession.self, 
            SessionMessage.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var standupWindowController: NSWindowController?
    var settingsWindowController: NSWindowController?
    var reminderTimer: Timer?
    private var modelContext: ModelContext?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 不出现在 Dock
        
        // Initialize model context
        modelContext = ModelContext(StandupAgentApp.sharedModelContainer)

        setupMenuBar()
        setupNotifications()
        scheduleNextReminder()
        
        // Register for standup completion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(standupSessionCompleted),
            name: .standupSessionCompleted,
            object: nil
        )

        // Debug: 通过启动参数直接打开早会窗口
        if CommandLine.arguments.contains("--open-standup") {
            DispatchQueue.main.async { [weak self] in
                self?.startStandup()
            }
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Standup")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "开始早会", action: #selector(startStandup), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - Standup Window

    @objc func startStandup() {
        if standupWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "早会"
            window.center()
            window.contentView = NSHostingView(rootView: StandupView()
                .modelContainer(StandupAgentApp.sharedModelContainer))
            standupWindowController = NSWindowController(window: window)
            window.delegate = self
        }
        standupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: window)
            window.delegate = self
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Notifications & Scheduling

    func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 将日期推进到最近的工作日（周一~周五），如已是工作日则原样返回
    private func nextWeekday(from date: Date) -> Date {
        let calendar = Calendar.current
        var d = date
        while calendar.isDateInWeekend(d) {
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }

    func scheduleNextReminder() {
        reminderTimer?.invalidate()
        let settings = AppSettings.shared
        guard settings.isReminderEnabled else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = settings.reminderHour
        components.minute = settings.reminderMinute
        components.second = 0

        guard var fireDate = calendar.date(from: components) else { return }

        // 周末不提醒，直接推到下周一
        if calendar.isDateInWeekend(fireDate) {
            fireDate = nextWeekday(from: fireDate)
            let interval = fireDate.timeIntervalSinceNow
            reminderTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: false) { [weak self] _ in
                self?.fireReminder()
            }
            return
        }

        // 如果今天的时间已过
        if fireDate <= Date() {
            // 今天早会还没做 → 立即提醒
            if !hasCompletedStandupToday() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.fireReminder()
                }
                return
            }
            // 今天已完成 → 推到下一个工作日
            fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
            fireDate = nextWeekday(from: fireDate)
        }

        let interval = fireDate.timeIntervalSinceNow
        reminderTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: false) { [weak self] _ in
            self?.fireReminder()
        }
    }

    func fireReminder() {
        // Check if today's standup is already completed
        if hasCompletedStandupToday() {
            // Standup already done today, just schedule next reminder
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.scheduleNextReminder()
            }
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "早会时间到了 ☕"
        content.body = "点击开始今天的早会，或稍后提醒"
        content.sound = .default
        content.categoryIdentifier = "STANDUP_REMINDER"

        // 注册 action category
        let startAction = UNNotificationAction(identifier: "START", title: "现在开始", options: .foreground)
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE", title: "推迟 10 分钟", options: [])
        let category = UNNotificationCategory(
            identifier: "STANDUP_REMINDER",
            actions: [startAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        let request = UNNotificationRequest(identifier: "standup", content: content, trigger: nil)
        center.add(request)
        
        // 兜底：无论用户是否点击通知，都调度下一个工作日的提醒
        // 如果用户点了通知按钮，handler 里的 scheduleNextReminder() 会覆盖这个 timer
        let settings = AppSettings.shared
        let calendar = Calendar.current
        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        tomorrowComponents.hour = settings.reminderHour
        tomorrowComponents.minute = settings.reminderMinute
        tomorrowComponents.second = 0
        if let todayFire = calendar.date(from: tomorrowComponents) {
            var nextFire = calendar.date(byAdding: .day, value: 1, to: todayFire) ?? todayFire
            nextFire = nextWeekday(from: nextFire)
            let interval = nextFire.timeIntervalSinceNow
            reminderTimer?.invalidate()
            reminderTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: false) { [weak self] _ in
                self?.fireReminder()
            }
        }
    }

    // UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "START", UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async {
                self.startStandup()
                self.scheduleNextReminder()
            }
        case "SNOOZE":
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                self.fireReminder()
            }
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    // MARK: - Helper Methods
    
    @objc private func standupSessionCompleted() {
        // When a standup is completed, we might want to cancel any pending notifications
        // But we'll let the scheduled check handle it naturally
    }
    
    private func hasCompletedStandupToday() -> Bool {
        guard let modelContext = modelContext else { return false }
        
        let todayKey = StandupSession.dateKey(from: Date())
        let descriptor = FetchDescriptor<StandupSession>(predicate: #Predicate { $0.dateString == todayKey })
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == standupWindowController?.window {
                standupWindowController = nil
            } else if window == settingsWindowController?.window {
                settingsWindowController = nil
            }
        }
    }
}
