import Foundation

// MARK: - Claude Service

class ClaudeService: ObservableObject {
    static let shared = ClaudeService()

    private let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private var currentTask: URLSessionDataTask?
    private var currentSession: URLSession?
    private var isCancelled = false
    private var retryCount = 0
    private let maxRetries = 2
    private var pendingRetry: (() -> Void)?

    func cancelStream() {
        isCancelled = true
        retryCount = 0
        pendingRetry = nil
        currentTask?.cancel()
        currentTask = nil
        currentSession?.invalidateAndCancel()
        currentSession = nil
    }

    private func createSession(delegate: StreamDelegate) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // 系统提示：早会引导 Agent
    private let systemPrompt = """
    你是一个专注、高效的早会引导 Agent。

    你的职责：
    1. 开场时，根据用户的本周目标，主动提出今天最值得聚焦的 1-3 件事
    2. 引导用户思考：今天的优先级、可能的障碍、需要的资源
    3. 对话简洁有力，避免废话，像一个好的 coach
    4. 如果用户没有设置本周目标，先帮他梳理今天想做什么

    风格：直接、友好、有点幽默，不要太正式。用中文回复。

    【格式要求（非常重要，必须严格遵守）】
    - 每一个事项/段落必须独占一行，行与行之间用空行分隔
    - 绝对不要把多个事项写在同一行，不管中间有没有 emoji 或符号
    - 不要用 "———" "---" 或其他符号当分隔符
    - emoji 只能放在行首，不能用来在同一行里隔开不同事项
    - 列表项格式：每条前面加 "1." "2." 或 "- "，每条占一行
    - 关键信息用 **加粗** 强调
    - 每条回复不超过 8 行

    正确示例：
    1. 医药方向准备
    上午主力，**交付物**：拆 JD

    2. 新加坡 Follow-up Email
    午饭前后，30 分钟搞定

    错误示例（禁止）：
    🥇 1. 医药方向 **时间**：上午 🥈 2. Email **时间**：午饭前
    """

    // 流式发送（真正的 streaming，使用 URLSessionDataDelegate）
    func streamMessage(
        messages: [ChatMessage],
        context: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        retryCount = 0
        isCancelled = false
        
        let performRequest: () -> Void = { [weak self] in
            self?.performStream(
                messages: messages,
                context: context,
                onChunk: onChunk,
                onComplete: onComplete,
                onError: onError
            )
        }
        
        pendingRetry = performRequest
        performRequest()
    }
    
    private func performStream(
        messages: [ChatMessage],
        context: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        let settings = AppSettings.shared

        var completed = false
        var errored = false
        
        func completeOnce() {
            guard !completed else { return }
            completed = true
            retryCount = 0
            DispatchQueue.main.async { onComplete() }
        }

        func errorOnce(_ msg: String, _ error: Error? = nil) {
            guard !errored, !self.isCancelled else { return }
            errored = true
            
            let errorMsg = self.classifyError(msg, error: error)
            
            if self.shouldRetry(errorMsg) && self.retryCount < self.maxRetries {
                self.retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.retryCount)) {
                    self.pendingRetry?()
                }
                return
            }
            
            retryCount = 0
            DispatchQueue.main.async { onError(errorMsg) }
        }

        func chunk(_ text: String) {
            DispatchQueue.main.async { onChunk(text) }
        }

        let request: URLRequest
        let handleEvent: (String) -> Void

        switch settings.provider {
        case .claude:
            guard !settings.claudeApiKey.isEmpty else {
                errorOnce("请先在设置中填入 Claude API Key")
                return
            }
            request = buildClaudeRequest(apiKey: settings.claudeApiKey, model: settings.claudeModel, messages: messages, context: context)
            handleEvent = { payload in
                self.handleClaudeEvent(payload, onChunk: chunk, onComplete: completeOnce, onError: { msg in errorOnce(msg, nil) })
            }
        case .openAI:
            guard !settings.openAIApiKey.isEmpty else {
                errorOnce("请先在设置中填入 OpenAI API Key")
                return
            }
            request = buildOpenAIRequest(apiKey: settings.openAIApiKey, model: settings.openAIModel, messages: messages, context: context)
            handleEvent = { payload in
                self.handleOpenAIEvent(payload, onChunk: chunk, onComplete: completeOnce, onError: { msg in errorOnce(msg, nil) })
            }
        case .gemini:
            guard !settings.geminiApiKey.isEmpty else {
                errorOnce("请先在设置中填入 Gemini API Key")
                return
            }
            guard let req = buildGeminiRequest(apiKey: settings.geminiApiKey, model: settings.geminiModel, messages: messages, context: context) else {
                errorOnce("Gemini 请求构建失败")
                return
            }
            request = req
            handleEvent = { payload in
                self.handleGeminiEvent(payload, onChunk: chunk, onComplete: completeOnce, onError: { msg in errorOnce(msg, nil) })
            }
        }

        let delegate = StreamDelegate(onEvent: handleEvent, onComplete: completeOnce, onError: errorOnce, onRetryableError: { [weak self] in
            guard let self = self, self.retryCount < self.maxRetries else { return false }
            self.retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.retryCount)) {
                self.pendingRetry?()
            }
            return true
        })
        let session = createSession(delegate: delegate)
        let task = session.dataTask(with: request)
        currentSession = session
        currentTask = task
        task.resume()
    }
    
    private func classifyError(_ msg: String, error: Error?) -> String {
        let nsError = error as NSError?
        
        if msg.contains("TLS") || msg.contains("SSL") || 
           nsError?.code == NSURLErrorSecureConnectionFailed {
            return "网络连接中断 (TLS错误)，已自动重试。如持续出现，请检查：\n1. 系统时间是否正确\n2. 是否使用 VPN/代理\n3. 切换网络环境"
        }
        
        if msg.contains("cancelled") || nsError?.code == NSURLErrorCancelled {
            return "请求已取消"
        }
        
        if msg.contains("timeout") || nsError?.code == NSURLErrorTimedOut {
            return "连接超时，正在重试..."
        }
        
        if msg.contains("network") || nsError?.code == NSURLErrorNotConnectedToInternet {
            return "网络未连接，请检查网络设置"
        }
        
        return msg
    }
    
    private func shouldRetry(_ msg: String) -> Bool {
        return msg.contains("TLS") || msg.contains("超时") || 
               msg.contains("network") || msg.contains("timeout")
    }

    private let formatReminder = """

【回复格式强制要求】每个事项必须单独一行，行间用空行隔开，禁止把多件事写在同一行里。
"""

    private func buildClaudeRequest(apiKey: String, model: String, messages: [ChatMessage], context: String) -> URLRequest {
        var apiMessages: [[String: Any]] = []
        for (i, msg) in messages.enumerated() {
            var textContent = msg.content
            if i == 0 && msg.role == .user {
                textContent = "【今日上下文】\n\(context)\(formatReminder)\n\n---\n\(msg.content)"
            }
            if msg.role == .user && !msg.images.isEmpty {
                var parts: [[String: Any]] = msg.images.map { img in
                    ["type": "image",
                     "source": ["type": "base64",
                                "media_type": img.mediaType,
                                "data": img.base64]]
                }
                if !textContent.isEmpty {
                    parts.append(["type": "text", "text": textContent])
                }
                apiMessages.append(["role": "user", "content": parts])
            } else {
                apiMessages.append([
                    "role": msg.role == .user ? "user" : "assistant",
                    "content": textContent
                ])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": systemPrompt,
            "messages": apiMessages
        ]

        var request = URLRequest(url: claudeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildOpenAIRequest(apiKey: String, model: String, messages: [ChatMessage], context: String) -> URLRequest {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for (i, msg) in messages.enumerated() {
            var textContent = msg.content
            if i == 0 && msg.role == .user {
                textContent = "【今日上下文】\n\(context)\(formatReminder)\n\n---\n\(msg.content)"
            }
            if msg.role == .user && !msg.images.isEmpty {
                var parts: [[String: Any]] = msg.images.map { img in
                    ["type": "image_url",
                     "image_url": ["url": "data:\(img.mediaType);base64,\(img.base64)"]]
                }
                if !textContent.isEmpty {
                    parts.insert(["type": "text", "text": textContent], at: 0)
                }
                apiMessages.append(["role": "user", "content": parts])
            } else {
                apiMessages.append([
                    "role": msg.role == .user ? "user" : "assistant",
                    "content": textContent
                ])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": 4096,
            "messages": apiMessages
        ]

        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildGeminiRequest(apiKey: String, model: String, messages: [ChatMessage], context: String) -> URLRequest? {
        let normalizedModel: String
        if model.hasPrefix("models/") {
            normalizedModel = String(model.dropFirst(7))
        } else {
            normalizedModel = model
        }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(normalizedModel):streamGenerateContent")
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { return nil }

        var contents: [[String: Any]] = []
        for (i, msg) in messages.enumerated() {
            var textContent = msg.content
            if i == 0 && msg.role == .user {
                textContent = "【系统指令】\n\(systemPrompt)\n\n【今日上下文】\n\(context)\(formatReminder)\n\n---\n\(msg.content)"
            }
            if msg.role == .user && !msg.images.isEmpty {
                var parts: [[String: Any]] = msg.images.map { img in
                    ["inline_data": ["mime_type": img.mediaType, "data": img.base64]]
                }
                if !textContent.isEmpty {
                    parts.append(["text": textContent])
                }
                contents.append(["role": "user", "parts": parts])
            } else {
                contents.append([
                    "role": msg.role == .user ? "user" : "model",
                    "parts": [["text": textContent]]
                ])
            }
        }

        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func handleClaudeEvent(_ payload: String, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String) -> Void) {
        if payload == "[DONE]" {
            onComplete()
            return
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = json["type"] as? String else { return }

        if type_ == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            onChunk(text)
            return
        }

        if type_ == "message_stop" {
            onComplete()
            return
        }

        if type_ == "error",
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            onError(msg)
            return
        }
    }

    private func handleOpenAIEvent(_ payload: String, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String) -> Void) {
        if payload == "[DONE]" {
            onComplete()
            return
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            onError(msg)
            return
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else { return }

        if let delta = first["delta"] as? [String: Any],
           let text = delta["content"] as? String {
            onChunk(text)
        }

        if first["finish_reason"] != nil {
            onComplete()
        }
    }

    private func handleGeminiEvent(_ payload: String, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String) -> Void) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            onError(msg)
            return
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return }

        for part in parts {
            if let text = part["text"] as? String {
                onChunk(text)
            }
        }

        if let reason = first["finishReason"] as? String, !reason.isEmpty {
            onComplete()
        }
    }
}

// MARK: - Streaming Delegate

class StreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private var errorBody = Data()
    private var httpStatusCode: Int?
    private let onEvent: (String) -> Void
    private let onComplete: () -> Void
    private let onError: (String, Error?) -> Void
    private let onRetryableError: () -> Bool

    init(onEvent: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String, Error?) -> Void, onRetryableError: @escaping () -> Bool = { false }) {
        self.onEvent = onEvent
        self.onComplete = onComplete
        self.onError = onError
        self.onRetryableError = onRetryableError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let code = httpStatusCode, code != 200 {
            errorBody.append(data)
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let code = httpStatusCode, code != 200 {
            let detail = String(data: errorBody, encoding: .utf8) ?? ""
            let msg: String
            if let data = detail.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let message = err["message"] as? String {
                msg = "HTTP \(code): \(message)"
            } else if !detail.isEmpty {
                msg = "HTTP \(code): \(String(detail.prefix(200)))"
            } else {
                msg = "HTTP \(code)"
            }
            DispatchQueue.main.async { self.onError(msg, nil) }
        } else if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorSecureConnectionFailed || 
               nsError.code == NSURLErrorServerCertificateHasBadDate ||
               nsError.code == NSURLErrorServerCertificateUntrusted {
                _ = self.onRetryableError()
            }
            DispatchQueue.main.async { self.onError(error.localizedDescription, error) }
        } else {
            DispatchQueue.main.async { self.onComplete() }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            httpStatusCode = httpResponse.statusCode
        }
        completionHandler(.allow)
    }

    private func processBuffer() {
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""

        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payloadStart = trimmed.index(trimmed.startIndex, offsetBy: 5)
            let payload = String(trimmed[payloadStart...]).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }
            onEvent(payload)
        }
    }
}
