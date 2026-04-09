import Foundation

@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?)

class NodeJSBridge {
    static let shared = NodeJSBridge()
    private var isNodeStarted = false
    private let httpSession = URLSession(configuration: .default)
    private let baseURL = "http://127.0.0.1:3000"

    private init() {
        Logger.shared.log("NodeJSBridge 初始化 (HTTP 模式)", level: .info)
        listAllScriptsInBundle()
        startNodeInBackground()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            self.testServerReady()
        }
    }

    private func listAllScriptsInBundle() {
        Logger.shared.log("扫描 Bundle 中的脚本文件...", level: .debug)
        guard let resourcePath = Bundle.main.resourcePath else {
            Logger.shared.log("无法获取 Bundle 资源路径", level: .warning)
            return
        }
        let enumerator = FileManager.default.enumerator(atPath: resourcePath)
        var found = false
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".js") || file.contains("type3") {
                Logger.shared.log("发现文件: \(file)", level: .info)
                found = true
            }
        }
        if !found {
            Logger.shared.log("未找到任何 .js 文件", level: .warning)
        }
    }

    private func findScriptPath() -> String? {
        // 尝试1：标准 nodejs-project 子目录
        if let path = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") {
            Logger.shared.log("路径1 命中: \(path)", level: .info)
            return path
        }
        // 尝试2：直接在资源根目录
        if let path = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: nil) {
            Logger.shared.log("路径2 命中: \(path)", level: .info)
            return path
        }
        // 尝试3：遍历查找
        if let resourcePath = Bundle.main.resourcePath,
           let enumerator = FileManager.default.enumerator(atPath: resourcePath) {
            while let file = enumerator.nextObject() as? String {
                if file.hasSuffix("type3-parser.js") {
                    let fullPath = (resourcePath as NSString).appendingPathComponent(file)
                    Logger.shared.log("路径3 命中: \(fullPath)", level: .info)
                    return fullPath
                }
            }
        }
        return nil
    }

    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true
        Logger.shared.log("准备启动 Node.js 线程", level: .info)

        Thread.detachNewThread {
            guard let scriptPath = self.findScriptPath() else {
                Logger.shared.log("❌ 未找到 Node 脚本！请检查 Bundle 资源", level: .error)
                return
            }
            Logger.shared.log("使用脚本路径: \(scriptPath)", level: .info)

            let args = ["node", scriptPath]
            var cArgs = args.map { strdup($0) }
            node_start(Int32(args.count), &cArgs)
            cArgs.forEach { free($0) }
            Logger.shared.log("node_start 已调用", level: .info)
        }

        Logger.shared.log("Node 线程已分离", level: .info)
    }

    private func testServerReady() {
        Logger.shared.log("测试 HTTP 服务器是否就绪...", level: .debug)
        var request = URLRequest(url: URL(string: "\(baseURL)/health")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        httpSession.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.shared.log("健康检查失败: \(error.localizedDescription)", level: .error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                Logger.shared.log("✅ HTTP 服务器已就绪", level: .info)
            } else {
                Logger.shared.log("健康检查响应异常: \(response?.description ?? "")", level: .warning)
            }
        }.resume()
    }

    // 内部方法：向 Node.js 发送任意 JSON 请求，并返回解析结果
    func sendRequest(jsonString: String, completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestId = UUID().uuidString.prefix(8)
        Logger.shared.log("[\(requestId)] 发送 HTTP 请求到 \(baseURL)/parse", level: .debug)

        guard let url = URL(string: "\(baseURL)/parse") else {
            completion(nil, NSError(domain: "NodeJSBridge", code: -1))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonString.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        httpSession.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.shared.log("[\(requestId)] 网络错误: \(error.localizedDescription)", level: .error)
                completion(nil, error)
                return
            }

            guard let data = data,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.shared.log("[\(requestId)] 响应非 JSON", level: .error)
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            if let success = result["success"] as? Bool, success {
                Logger.shared.log("[\(requestId)] 解析成功", level: .info)
                completion(result["data"] as? [String: Any], nil)
            } else {
                let errorMsg = result["error"] as? String ?? "解析失败"
                Logger.shared.log("[\(requestId)] Node 错误: \(errorMsg)", level: .error)
                completion(nil, NSError(domain: "NodeJSBridge", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }
        }.resume()
    }

    // 兼容旧接口
    func parseType3Source(sourceUrl: String,
                          headers: [String: String]? = nil,
                          completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestData: [String: Any] = [
            "url": sourceUrl,
            "headers": headers ?? [:]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(nil, NSError(domain: "NodeJSBridge", code: -2))
            return
        }
        sendRequest(jsonString: jsonString, completion: completion)
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
