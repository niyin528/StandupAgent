import SwiftUI
import SwiftData

struct StandupView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var editingMessageId: UUID?
    @State private var editText = ""
    @State private var attachedImages: [AttachedImage] = []
    @FocusState private var inputFocused: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            header

            Divider()

            // ── Chat area ──
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty && !isLoading {
                            emptyState
                        } else {
                            ForEach(messages) { msg in
                                MessageBubble(
                                    message: msg,
                                    isEditing: editingMessageId == msg.id,
                                    isLoading: isLoading,
                                    editText: $editText,
                                    onStartEdit: {
                                        editText = msg.content
                                        editingMessageId = msg.id
                                    },
                                    onSaveEdit: {
                                        editAndResend(messageId: msg.id)
                                    },
                                    onCancelEdit: {
                                        editingMessageId = nil
                                        editText = ""
                                    }
                                )
                                    .id(msg.id)
                            }
                        }
                        if let err = errorMessage {
                            errorBanner(err)
                        }
                        // 滚动锚点
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: messages.last?.content) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            Divider()

            // ── Input bar ──
            inputBar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadMessages(for: selectedDate)
            if isToday && messages.isEmpty {
                startStandup()
            }
            inputFocused = true
        }
        .onChange(of: selectedDate) { [selectedDate] newDate in
            saveCurrentMessages(for: selectedDate)
            messages = []
            errorMessage = nil
            isLoading = false
            editingMessageId = nil
            editText = ""
            loadMessages(for: newDate)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: goToPreviousDay) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            VStack(spacing: 2) {
                Text("早会 ☕")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(dateTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !isToday {
                        Text("(历史)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if hasSession(for: selectedDate) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .disabled(isLoading)
            .onTapGesture { if !isLoading { showDatePicker.toggle() } }
            .popover(isPresented: $showDatePicker) {
                DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .disabled(isLoading)
                    .onChange(of: selectedDate) { _ in
                        showDatePicker = false
                    }
            }

            Button(action: goToNextDay) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isToday || isLoading)

            Spacer()

            if !isToday {
                Button("回到今天") {
                    selectedDate = Date()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isToday ? "cup.and.saucer.fill" : "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(isToday ? "正在准备今天的早会…" : "这天没有早会记录")
                .foregroundStyle(.secondary)
            if isToday {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedImages) { img in
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: img.nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                                Button {
                                    attachedImages.removeAll { $0.id == img.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                }
            }
            HStack(spacing: 10) {
                PasteAwareTextField(
                    placeholder: "",
                    text: $inputText,
                    onPasteImage: { image in
                        attachedImages.append(AttachedImage(nsImage: image))
                    },
                    onSubmit: { sendMessage() }
                )
                .focused($inputFocused)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: isLoading ? stopStream : sendMessage) {
                    Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle((inputText.isEmpty && attachedImages.isEmpty && !isLoading) ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty && attachedImages.isEmpty && !isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("关闭") { errorMessage = nil }
                .buttonStyle(.plain)
                .font(.callout)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Date Navigation

    private func goToPreviousDay() {
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = prev
        }
    }

    private func goToNextDay() {
        guard !isToday else { return }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = next
        }
    }

    // MARK: - Persistence

    private func hasSession(for date: Date) -> Bool {
        let key = StandupSession.dateKey(from: date)
        let descriptor = FetchDescriptor<StandupSession>(predicate: #Predicate { $0.dateString == key })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    private func loadMessages(for date: Date) {
        let key = StandupSession.dateKey(from: date)
        var descriptor = FetchDescriptor<StandupSession>(predicate: #Predicate { $0.dateString == key })
        descriptor.fetchLimit = 1

        guard let session = (try? modelContext.fetch(descriptor))?.first else {
            messages = []
            return
        }

        messages = session.sortedMessages.map { sm in
            ChatMessage(role: sm.role == "user" ? .user : .assistant, content: sm.content)
        }
    }

    private func saveCurrentMessages(for date: Date? = nil) {
        guard !messages.isEmpty else { return }

        let targetDate = date ?? selectedDate
        let key = StandupSession.dateKey(from: targetDate)
        var descriptor = FetchDescriptor<StandupSession>(predicate: #Predicate { $0.dateString == key })
        descriptor.fetchLimit = 1

        let session: StandupSession
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // 清除旧消息再重写
            for msg in existing.messages {
                modelContext.delete(msg)
            }
            session = existing
        } else {
            session = StandupSession(dateString: key)
            modelContext.insert(session)
        }

        for (i, msg) in messages.enumerated() {
            let sm = SessionMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content,
                orderIndex: i,
                session: session
            )
            session.messages.append(sm)
        }

        try? modelContext.save()

        // Post notification if today's session was saved
        if Calendar.current.isDateInToday(targetDate) {
            NotificationCenter.default.post(name: .standupSessionCompleted, object: nil)
        }
    }

    // MARK: - Weekly Memory

    /// 获取本周一到昨天的早会对话，压缩后作为上下文
    private func buildWeeklyMemory() -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 计算本周一
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Sun=1 → 6, Mon=2 → 0, Tue=3 → 1 ...
        guard daysFromMonday > 0,
              let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return "" // 今天就是周一，没有本周历史
        }

        let mondayKey = StandupSession.dateKey(from: monday)
        let todayKey = StandupSession.dateKey(from: today)

        let descriptor = FetchDescriptor<StandupSession>(
            predicate: #Predicate<StandupSession> { session in
                session.dateString >= mondayKey && session.dateString < todayKey
            },
            sortBy: [SortDescriptor(\StandupSession.dateString)]
        )

        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else {
            return ""
        }

        let maxCharsPerDay = 5000
        var memory = "【本周早会回顾（压缩）】\n"

        for session in sessions {
            memory += "\n📅 \(session.dateString):\n"
            var dayContent = ""
            for msg in session.sortedMessages where msg.role == "user" {
                let line = "- \(msg.content)\n"
                if dayContent.count + line.count <= maxCharsPerDay {
                    dayContent += line
                } else {
                    dayContent += "- …（更多内容已省略）\n"
                    break
                }
            }
            if dayContent.isEmpty {
                dayContent = "（无用户发言记录）\n"
            }
            memory += dayContent
        }

        return memory
    }

    // MARK: - Actions

    private func startStandup() {
        guard messages.isEmpty else { return }
        let openingMsg = ChatMessage(role: .user, content: "早会开始，帮我引导一下今天")
        messages.append(openingMsg)
        fetchReply()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty else { return }
        let imgs = attachedImages
        inputText = ""
        attachedImages = []
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text, images: imgs))
        fetchReply()
    }

    private func editAndResend(messageId: UUID) {
        guard !isLoading else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        messages[index].content = newContent
        messages = Array(messages.prefix(index + 1))

        editingMessageId = nil
        editText = ""
        errorMessage = nil
        fetchReply()
    }

    private func stopStream() {
        LLMService.shared.cancelStream()
        if let last = messages.last, last.role == .assistant {
            if last.content.isEmpty {
                messages.removeLast()
            } else {
                messages[messages.count - 1].isStreaming = false
            }
        }
        isLoading = false
    }

    private func fetchReply() {
        isLoading = true
        let currentDate = selectedDate // 捕获当前日期，防止切换后保存到错误日期
        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let idx = messages.count - 1
        let messagesToSend = Array(messages.dropLast())
        let baseContext = settings.buildContext()

        let weeklyMemory = buildWeeklyMemory()
        let fullContext = baseContext + "\n" + weeklyMemory

        DispatchQueue.global(qos: .userInitiated).async {
            LLMService.shared.streamMessage(
                messages: messagesToSend,
                context: fullContext,
                onChunk: { chunk in
                    if idx < self.messages.count {
                        self.messages[idx].content += chunk
                    }
                },
                onComplete: {
                    if idx < self.messages.count {
                        self.messages[idx].isStreaming = false
                        self.isLoading = false
                        self.saveCurrentMessages(for: currentDate)
                    }
                },
                onError: { err in
                    if idx < self.messages.count {
                        self.messages.removeLast()
                    }
                    self.errorMessage = err
                    self.isLoading = false
                }
            )
        }
    }
}

// MARK: - Message Bubble

private func markdownAttributed(_ string: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
    return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
}

struct MessageBubble: View {
    let message: ChatMessage
    let isEditing: Bool
    let isLoading: Bool
    @Binding var editText: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
                if isEditing {
                    editView
                } else {
                    userBubble
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(Circle())
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if message.content.isEmpty && message.isStreaming {
                        // 打字指示器
                        TypingIndicator()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(message.content.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    Text(markdownAttributed(trimmed))
                                        .textSelection(.enabled)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if message.isStreaming && !message.content.isEmpty {
                        // 流式光标
                        Text("▌")
                            .foregroundStyle(.purple.opacity(0.6))
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 60)
            }
        }
    }

    @State private var isHovering = false

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onStartEdit) {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .opacity(isHovering && !isLoading ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.15), value: isHovering)

            VStack(alignment: .trailing, spacing: 6) {
                if !message.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.images) { img in
                            Image(nsImage: img.nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.25), lineWidth: 1))
                        }
                    }
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var editView: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                )
            HStack(spacing: 12) {
                Button("取消") { onCancelEdit() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: onSaveEdit) {
                    Label("发送", systemImage: "arrow.up.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.secondary)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear {
            phase = 1
        }
    }
}


// MARK: - Paste-Aware Text Field

struct PasteAwareTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onPasteImage: (NSImage) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onPasteImage: onPasteImage, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> PasteTextField {
        let field = PasteTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.onPasteImage = onPasteImage
        field.isEditable = true
        field.isSelectable = true
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 5
        field.lineBreakMode = .byWordWrapping
        return field
    }

    func updateNSView(_ nsView: PasteTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onPasteImage: (NSImage) -> Void
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onPasteImage: @escaping (NSImage) -> Void, onSubmit: @escaping () -> Void) {
            _text = text
            self.onPasteImage = onPasteImage
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter key pressed - trigger submit
                onSubmit?()
                return true
            }
            return false
        }
    }
}

class PasteTextField: NSTextField {
    var onPasteImage: ((NSImage) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            return handlePaste()
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    private func handlePaste() -> Bool {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb) {
            DispatchQueue.main.async { self.onPasteImage?(image) }
            return true
        }
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        return true
    }
}

// MARK: - Previews

struct StandupView_Previews: PreviewProvider {
    static var previews: some View {
        StandupView()
            .frame(width: 720, height: 600)
    }
}
