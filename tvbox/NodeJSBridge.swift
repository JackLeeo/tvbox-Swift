import Foundation

// RN 插件版框架导出的 C API
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
        registerNodeMessageCallback()
        startNodeInBackground()
    }

    private func registerNodeMessageCallback() {
        node_register_message_callback { msgPtr in
            guard let msgPtr = msgPtr else { return }
            let message = String(cString: msgPtr)
            DispatchQueue.main.async {
                NodeJSBridge.shared.handleNodeMessage(message)
            }
        }
    }

    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true

        Thread.detachNewThread {
            guard let scriptPath = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") else {
                print("❌ Node 脚本路径不存在")
                return
            }
            scriptPath.withCString { cStr in
                node_start(cStr)
            }
        }
    }

    private func handleNodeMessage(_ message: String) {
        do {
            guard let data = message.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requestId = result["id"] as? String,
                  let completion = pendingCompletions.removeValue(forKey: requestId) else { return }

            if let success = result["success"] as? Bool, success {
                completion(result["data"] as? [String: Any], nil)
            } else {
                let error = NSError(domain: "NodeJSBridge", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: result["error"] as? String ?? "解析失败"
                ])
                completion(nil, error)
            }
        } catch {
            print("❌ 处理Node消息失败: \(error)")
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
            completion(nil, NSError(domain: "NodeJSBridge", code: -2))
            return
        }

        jsonString.withCString { ptr in
            node_post_message(ptr)
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
