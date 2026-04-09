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
        Logger.shared.log("NodeJSBridge 初始化（HTTP 模式）", level: .info)
        startNodeInBackground()
        // 延迟 2 秒后测试服务器是否就绪
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            self.testServerReady()
        }
    }

    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true
        Logger.shared.log("准备启动 Node.js 线程", level: .info)

        Thread.detachNewThread {
            guard let scriptPath = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") else {
                Logger.shared.log("❌ Node 脚本路径不存在！请检查 Bundle 资源", level: .error)
                return
            }
            Logger.shared.log("✅ 脚本路径: \(scriptPath)", level: .info)

            let args = ["node", scriptPath]
            var cArgs = args.map { strdup($0) }
            node_start(Int32(args.count), &cArgs)
            cArgs.forEach { free($0) }
            Logger.shared.log("▶️ node_start 已调用（注意：此函数通常不会返回）", level: .info)
        }

        Logger.shared.log("Node 线程已分离，等待服务器启动...", level: .info)
    }

    /// 测试 HTTP 服务器是否已经可以接受请求
    private func testServerReady() {
        Logger.shared.log("🔍 开始测试 HTTP 服务器是否就绪...", level: .debug)

        var request = URLRequest(url: URL(string: "\(baseURL)/health")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        let task = httpSession.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.shared.log("❌ 服务器健康检查失败: \(error.localizedDescription)", level: .error)
                Logger.shared.log("💡 可能原因：Node.js 启动失败、端口被占用、脚本执行出错", level: .error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Logger.shared.log("✅ HTTP 服务器已就绪，健康检查响应: \(body)", level: .info)
            } else {
                Logger.shared.log("⚠️ 服务器响应异常: \(String(describing: response))", level: .warning)
            }
        }
        task.resume()
    }

    func parseType3Source(sourceUrl: String,
                          headers: [String: String]? = nil,
                          completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestId = UUID().uuidString.prefix(8)
        Logger.shared.log("[\(requestId)] 发送 HTTP 请求到 \(baseURL)/parse", level: .debug)
        Logger.shared.log("[\(requestId)] 请求 URL: \(sourceUrl)", level: .debug)

        let requestData: [String: Any] = [
            "url": sourceUrl,
            "headers": headers ?? [:]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            Logger.shared.log("[\(requestId)] 无法序列化请求数据", level: .error)
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
                Logger.shared.log("[\(requestId)] 网络错误: \(error.localizedDescription)", level: .error)
                completion(nil, error)
                return
            }

            guard let data = data else {
                Logger.shared.log("[\(requestId)] 响应数据为空", level: .error)
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let responseStr = String(data: data, encoding: .utf8) ?? "无法解析"
                Logger.shared.log("[\(requestId)] 响应不是有效 JSON: \(responseStr.prefix(200))", level: .error)
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            if let success = result["success"] as? Bool, success {
                Logger.shared.log("[\(requestId)] 解析成功", level: .info)
                completion(result["data"] as? [String: Any], nil)
            } else {
                let errorMsg = result["error"] as? String ?? "解析失败"
                Logger.shared.log("[\(requestId)] Node 返回错误: \(errorMsg)", level: .error)
                completion(nil, NSError(domain: "NodeJSBridge", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }
        }
        task.resume()
        Logger.shared.log("[\(requestId)] 请求已发出，等待响应...", level: .debug)
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
