import Foundation

// RN 插件版框架的 C API 签名
@_silgen_name("node_start")
func node_start(_ scriptPath: UnsafePointer<CChar>)

@_silgen_name("node_register_message_callback")
func node_register_message_callback(_ callback: @convention(c) (UnsafePointer<CChar>?) -> Void)

@_silgen_name("node_post_message")
func node_post_message(_ message: UnsafePointer<CChar>?)

class NodeJSBridge {
    static let shared = NodeJSBridge()
    private var isNodeStarted = false
    private var pendingCompletions: [String: ([String: Any]?, Error?) -> Void] = [:]
    
    private init() {
        Logger.shared.log("NodeJSBridge 初始化", level: .info)
        registerNodeMessageCallback()
        startNodeInBackground()
    }
    
    private func registerNodeMessageCallback() {
        Logger.shared.log("注册 Node 消息回调", level: .info)
        node_register_message_callback { msgPtr in
            guard let msgPtr = msgPtr else {
                Logger.shared.log("收到空消息指针", level: .warning)
                return
            }
            let message = String(cString: msgPtr)
            Logger.shared.log("收到 Node 消息: \(message.prefix(150))...", level: .debug)
            DispatchQueue.main.async {
                NodeJSBridge.shared.handleNodeMessage(message)
            }
        }
    }
    
    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true
        Logger.shared.log("准备启动 Node.js 线程", level: .info)
        
        let nodeThread = Thread {
            guard let scriptPath = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") else {
                Logger.shared.log("❌ Node 脚本路径不存在！请检查 Bundle 资源", level: .error)
                return
            }
            Logger.shared.log("Node 脚本路径: \(scriptPath)", level: .info)
            scriptPath.withCString { cStr in
                Logger.shared.log("调用 node_start", level: .info)
                node_start(cStr)
            }
        }
        nodeThread.stackSize = 2 * 1024 * 1024
        nodeThread.start()
        Logger.shared.log("Node 线程已启动，栈大小: \(nodeThread.stackSize / 1024) KB", level: .info)
    }
    
    private func handleNodeMessage(_ message: String) {
        Logger.shared.log("处理 Node 消息: \(message.prefix(100))...", level: .debug)
        do {
            guard let data = message.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requestId = result["id"] as? String,
                  let completion = pendingCompletions.removeValue(forKey: requestId) else {
                Logger.shared.log("消息格式不符或未找到对应请求 ID", level: .warning)
                return
            }
            
            if let success = result["success"] as? Bool, success {
                Logger.shared.log("请求成功 (id: \(requestId))", level: .info)
                completion(result["data"] as? [String: Any], nil)
            } else {
                let errorMsg = result["error"] as? String ?? "解析失败"
                Logger.shared.log("Node 返回错误 (id: \(requestId)): \(errorMsg)", level: .error)
                let error = NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                completion(nil, error)
            }
        } catch {
            Logger.shared.log("解析 Node 消息异常: \(error)", level: .error)
        }
    }
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestId = UUID().uuidString
        pendingCompletions[requestId] = completion
        
        let requestData: [String: Any] = [
            "id": requestId,
            "url": sourceUrl,
            "headers": headers ?? [
                "User-Agent": "tvbox-Swift/1.0.0",
                "Referer": "https://tvbox.example.com"
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(nil, NSError(domain: "NodeJSBridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效的请求数据"]))
            return
        }
        
        Logger.shared.log("发送 Node 请求 (id: \(requestId)): \(jsonString.prefix(150))...", level: .debug)
        jsonString.withCString { ptr in
            node_post_message(ptr)
        }
        
        // 超时处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.pendingCompletions[requestId] != nil else { return }
            self.pendingCompletions.removeValue(forKey: requestId)
            Logger.shared.log("请求超时 (id: \(requestId))", level: .error)
            completion(nil, NSError(domain: "NodeJSBridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "请求超时"]))
        }
    }
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            parseType3Source(sourceUrl: sourceUrl, headers: headers) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "NodeJSBridge", code: -1))
                }
            }
        }
    }
}
