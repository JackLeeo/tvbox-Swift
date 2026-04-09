import Foundation

// 官方原生框架 C API 声明（双参数 node_start）
@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?)

class NodeJSBridge {
    static let shared = NodeJSBridge()
    private var isNodeStarted = false
    private let httpSession = URLSession(configuration: .default)
    private let baseURL = "http://127.0.0.1:3000"

    private init() {
        print("📱 NodeJSBridge 初始化（HTTP 模式）")
        startNodeInBackground()
    }

    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true
        print("🚀 准备启动 Node.js 线程")

        Thread.detachNewThread {
            guard let scriptPath = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") else {
                print("❌ Node 脚本路径不存在！请检查 Bundle 资源")
                return
            }
            print("✅ 脚本路径: \(scriptPath)")

            let args = ["node", scriptPath]
            var cArgs = args.map { strdup($0) }
            node_start(Int32(args.count), &cArgs)
            cArgs.forEach { free($0) }
            print("▶️ node_start 已调用")
        }

        // 等待服务器启动
        print("⏳ 等待 HTTP 服务器就绪（1秒）...")
        Thread.sleep(forTimeInterval: 1.0)
        print("✅ 等待结束，可以开始发送请求")
    }

    func parseType3Source(sourceUrl: String,
                          headers: [String: String]? = nil,
                          completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestId = UUID().uuidString.prefix(8)
        print("📤 [\(requestId)] 发送 HTTP 请求到 \(baseURL)/parse")
        print("📤 [\(requestId)] 请求 URL: \(sourceUrl)")

        let requestData: [String: Any] = [
            "url": sourceUrl,
            "headers": headers ?? [:]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            print("❌ [\(requestId)] 无法序列化请求数据")
            completion(nil, NSError(domain: "NodeJSBridge", code: -2))
            return
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/parse")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let task = httpSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [\(requestId)] 网络错误: \(error.localizedDescription)")
                completion(nil, error)
                return
            }

            guard let data = data else {
                print("❌ [\(requestId)] 响应数据为空")
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let responseStr = String(data: data, encoding: .utf8) ?? "无法解析"
                print("❌ [\(requestId)] 响应不是有效 JSON: \(responseStr.prefix(200))")
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            if let success = result["success"] as? Bool, success {
                print("✅ [\(requestId)] 解析成功")
                completion(result["data"] as? [String: Any], nil)
            } else {
                let errorMsg = result["error"] as? String ?? "解析失败"
                print("❌ [\(requestId)] Node 返回错误: \(errorMsg)")
                completion(nil, NSError(domain: "NodeJSBridge", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }
        }
        task.resume()
        print("📤 [\(requestId)] 请求已发出，等待响应...")
    }

    func parseType3Source(sourceUrl: String,
                          headers: [String: String]? = nil) async throws -> [String: Any] {
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
