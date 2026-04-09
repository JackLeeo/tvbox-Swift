import Foundation

@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?)

class NodeJSBridge {
    static let shared = NodeJSBridge()
    private var isNodeStarted = false
    private let httpSession = URLSession(configuration: .default)
    private let baseURL = "http://127.0.0.1:3000"

    private init() {
        startNodeInBackground()
    }

    private func startNodeInBackground() {
        guard !isNodeStarted else { return }
        isNodeStarted = true

        Thread.detachNewThread {
            guard let scriptPath = Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project") else {
                print("❌ Node 脚本路径不存在")
                return
            }

            let args = ["node", scriptPath]
            var cArgs = args.map { strdup($0) }
            node_start(Int32(args.count), &cArgs)
            cArgs.forEach { free($0) }
        }

        // 等待服务器启动
        Thread.sleep(forTimeInterval: 1.0)
    }

    func parseType3Source(sourceUrl: String,
                          headers: [String: String]? = nil,
                          completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestData: [String: Any] = [
            "url": sourceUrl,
            "headers": headers ?? [:]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData) else {
            completion(nil, NSError(domain: "NodeJSBridge", code: -2))
            return
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/parse")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        httpSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let data = data,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, NSError(domain: "NodeJSBridge", code: -3))
                return
            }

            if let success = result["success"] as? Bool, success {
                completion(result["data"] as? [String: Any], nil)
            } else {
                let errorMsg = result["error"] as? String ?? "解析失败"
                completion(nil, NSError(domain: "NodeJSBridge", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }
        }.resume()
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
