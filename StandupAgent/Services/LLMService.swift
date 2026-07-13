import Foundation

// MARK: - LLM Service

class LLMService: ObservableObject {
    static let shared = LLMService()

    private let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let deepseekEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    private var currentTask: URLSessionDataTask?
    private var currentSession: URLSession?
    private var isCancelled = false
    private var retryCount = 0
    private let maxRetries = 2
    private var pendingRetry: (() -> Void)?
    private var receivedFirstChunk = false

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[StandupAgent/LLM \(formatter.string(from: Date()))] \(message)")
    }

    private func invalidateCurrentSession() {
        currentTask?.cancel()
        currentTask = nil
        currentSession?.invalidateAndCancel()
        currentSession = nil
    }

    /// 统一重试入口，避免 delegate 与 errorOnce 双重递增 retryCount
    @discardableResult
    private func scheduleRetry(reason: String) -> Bool {
        guard !isCancelled, retryCount < maxRetries else {
            log("重试已耗尽或已取消 (retryCount=\(retryCount)/\(maxRetries), reason=\(reason))")
            return false
        }
        retryCount += 1
        log("计划重试 \(retryCount)/\(maxRetries)，\(retryCount)s 后执行，原因: \(reason)")
        invalidateCurrentSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryCount)) { [weak self] in
            guard let self, !self.isCancelled else {
                self?.log("重试已跳过（用户取消）")
                return
            }
            self.log("开始第 \(self.retryCount) 次重试")
            self.pendingRetry?()
        }
        return true
    }

    func cancelStream() {
        log("用户取消流式请求")
        isCancelled = true
        retryCount = 0
        pendingRetry = nil
        receivedFirstChunk = false
        invalidateCurrentSession()
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

    格式：关键信息用 **加粗** 强调。
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
        receivedFirstChunk = false
        log("streamMessage 开始，provider=\(AppSettings.shared.provider.displayName)，消息数=\(messages.count)，上下文=\(context.count) 字符")

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
        let attempt = retryCount + 1
        log("performStream 第 \(attempt) 次请求，provider=\(settings.provider.displayName)")

        var completed = false
        var errored = false
        
        func completeOnce() {
            guard !completed else { return }
            completed = true
            retryCount = 0
            log("流式响应完成")
            DispatchQueue.main.async { onComplete() }
        }

        func errorOnce(_ msg: String, _ error: Error? = nil) {
            guard !errored, !self.isCancelled else { return }
            errored = true

            let nsError = error as NSError?
            if nsError?.code == NSURLErrorCancelled || msg.lowercased().contains("cancelled") {
                log("请求已取消，不重试")
                retryCount = 0
                DispatchQueue.main.async { onError("请求已取消") }
                return
            }

            let errorMsg = self.classifyError(msg, error: error)
            log("请求失败: \(msg)\(error.map { " | \($0.localizedDescription)" } ?? "")")

            if self.shouldRetry(errorMsg, error: error), self.scheduleRetry(reason: errorMsg) {
                return
            }

            retryCount = 0
            log("最终失败，通知 UI: \(errorMsg)")
            DispatchQueue.main.async { onError(errorMsg) }
        }

        func chunk(_ text: String) {
            if !receivedFirstChunk {
                receivedFirstChunk = true
                log("收到首个内容块 (\(text.count) 字符)")
            }
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
            request = buildOpenAIRequest(endpoint: openAIEndpoint, apiKey: settings.openAIApiKey, model: settings.openAIModel, messages: messages, context: context)
            handleEvent = { payload in
                self.handleOpenAIEvent(payload, onChunk: chunk, onComplete: completeOnce, onError: { msg in errorOnce(msg, nil) })
            }
        case .deepseek:
            guard !settings.deepseekApiKey.isEmpty else {
                errorOnce("请先在设置中填入 DeepSeek API Key")
                return
            }
            request = buildOpenAIRequest(endpoint: deepseekEndpoint, apiKey: settings.deepseekApiKey, model: settings.deepseekModel, messages: messages, context: context)
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

        invalidateCurrentSession()

        let modelName: String
        switch settings.provider {
        case .claude: modelName = settings.claudeModel
        case .openAI: modelName = settings.openAIModel
        case .gemini: modelName = settings.geminiModel
        case .deepseek: modelName = settings.deepseekModel
        }
        log("发起 HTTP 请求，model=\(modelName)，url=\(request.url?.host ?? "?")")

        let delegate = StreamDelegate(onEvent: handleEvent, onComplete: completeOnce, onError: errorOnce)
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
    
    private func shouldRetry(_ msg: String, error: Error? = nil) -> Bool {
        let nsError = error as NSError?
        if nsError?.code == NSURLErrorSecureConnectionFailed ||
           nsError?.code == NSURLErrorServerCertificateHasBadDate ||
           nsError?.code == NSURLErrorServerCertificateUntrusted ||
           nsError?.code == NSURLErrorTimedOut ||
           nsError?.code == NSURLErrorNotConnectedToInternet ||
           nsError?.code == NSURLErrorNetworkConnectionLost {
            return true
        }
        return msg.contains("TLS") || msg.contains("超时") ||
               msg.contains("network") || msg.contains("timeout")
    }

    private func buildClaudeRequest(apiKey: String, model: String, messages: [ChatMessage], context: String) -> URLRequest {
        var apiMessages: [[String: Any]] = []
        for (i, msg) in messages.enumerated() {
            var textContent = msg.content
            if i == 0 && msg.role == .user {
                textContent = "【今日上下文】\n\(context)\n\n---\n\(msg.content)"
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

    private func buildOpenAIRequest(endpoint: URL, apiKey: String, model: String, messages: [ChatMessage], context: String) -> URLRequest {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for (i, msg) in messages.enumerated() {
            var textContent = msg.content
            if i == 0 && msg.role == .user {
                textContent = "【今日上下文】\n\(context)\n\n---\n\(msg.content)"
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

        var request = URLRequest(url: endpoint)
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
                textContent = "【系统指令】\n\(systemPrompt)\n\n【今日上下文】\n\(context)\n\n---\n\(msg.content)"
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

    init(onEvent: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String, Error?) -> Void) {
        self.onEvent = onEvent
        self.onComplete = onComplete
        self.onError = onError
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[StandupAgent/LLM \(formatter.string(from: Date()))] \(message)")
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
                msg = "HTTP \(code): \(message)" + (code == 403 ? "\n⚠️ 403 通常表示访问被拦截，请检查 VPN 是否已开启" : "")
            } else if !detail.isEmpty {
                msg = "HTTP \(code): \(String(detail.prefix(200)))" + (code == 403 ? "\n⚠️ 403 通常表示访问被拦截，请检查 VPN 是否已开启" : "")
            } else {
                msg = "HTTP \(code)" + (code == 403 ? "\n⚠️ 403 通常表示访问被拦截，请检查 VPN 是否已开启" : "")
            }
            log("HTTP 错误响应: \(msg)")
            DispatchQueue.main.async { self.onError(msg, nil) }
        } else if let error = error {
            log("URLSession 完成但有错误: \(error.localizedDescription) (code=\((error as NSError).code))")
            DispatchQueue.main.async { self.onError(error.localizedDescription, error) }
        } else {
            log("URLSession 正常完成")
            DispatchQueue.main.async { self.onComplete() }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            httpStatusCode = httpResponse.statusCode
            log("收到 HTTP 响应，status=\(httpResponse.statusCode)")
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
