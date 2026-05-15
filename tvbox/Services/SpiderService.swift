import Foundation

enum SpiderError: LocalizedError {
    case spiderNotSet
    case nodeNotReady
    case invalidResponse
    case httpError(Int)
    case timeout
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .spiderNotSet: return "Spider未设置"
        case .nodeNotReady: return "Node.js未就绪"
        case .invalidResponse: return "无效的响应"
        case .httpError(let code): return "HTTP错误: \(code)"
        case .timeout: return "请求超时"
        case .decodingError(let msg): return "解码错误: \(msg)"
        }
    }
}

class SpiderService {
    static let shared = SpiderService()

    private let session: URLSession
    private let maxRetries = 3
    private let timeoutInterval: TimeInterval = 30

    private var currentKey: String?
    private var currentType: Int?
    private var currentApiBase: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Spider状态管理

    func setCurrentSpider(key: String, type: Int, apiBase: String) {
        self.currentKey = key
        self.currentType = type
        self.currentApiBase = apiBase
    }

    // MARK: - 端口与状态

    private var spiderPort: Int {
        return Int(NodeJSManager.shared().getSpiderPort())
    }

    private var managementPort: Int {
        return Int(NodeJSManager.shared().getManagementPort())
    }

    private var isNodeReady: Bool {
        return NodeJSManager.shared().isNodeReady
    }

    // MARK: - URL构建

    private func buildURL(port: Int, path: String) throws -> URL {
        guard isNodeReady else {
            throw SpiderError.nodeNotReady
        }
        guard port > 0 else {
            throw SpiderError.nodeNotReady
        }
        let urlString = "http://127.0.0.1:\(port)\(path)"
        guard let url = URL(string: urlString) else {
            throw SpiderError.invalidResponse
        }
        return url
    }

    private func buildSpiderPath(action: String) throws -> String {
        if let apiBase = currentApiBase, !apiBase.isEmpty {
            return "\(apiBase)/\(action)"
        }
        guard let key = currentKey, let type = currentType else {
            throw SpiderError.spiderNotSet
        }
        return "/\(key)/\(type)/\(action)"
    }

    // MARK: - 核心POST请求（带重试）

    private func postJSON(
        path: String,
        port: Int,
        body: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let url = try buildURL(port: port, path: path)
        let requestBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error?
        let totalAttempts = maxRetries + 1

        for attempt in 0..<totalAttempts {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = requestBody
                request.timeoutInterval = timeoutInterval

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SpiderError.invalidResponse
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw SpiderError.httpError(httpResponse.statusCode)
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw SpiderError.decodingError("响应不是有效的JSON对象")
                }

                return json
            } catch let error as SpiderError {
                throw error
            } catch {
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut

                if isTimeout && attempt < totalAttempts - 1 {
                    lastError = error
                    let delay = TimeInterval(attempt + 1)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                if isTimeout {
                    throw SpiderError.timeout
                }
                throw error
            }
        }

        throw lastError ?? SpiderError.timeout
    }

    // MARK: - Spider API

    func getCatConfig() async throws -> [String: Any] {
        guard spiderPort > 0 else {
            throw SpiderError.nodeNotReady
        }
        let url = try buildURL(port: spiderPort, path: "/config")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpiderError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpiderError.httpError(httpResponse.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpiderError.decodingError("config响应不是有效的JSON对象")
        }
        return json
    }

    func initSpider() async throws {
        let path = try buildSpiderPath(action: "init")
        _ = try await postJSON(path: path, port: spiderPort, body: [:])
    }

    func getHomeContent() async throws -> [String: Any] {
        let path = try buildSpiderPath(action: "home")
        return try await postJSON(path: path, port: spiderPort, body: [:])
    }

    func getCategoryContent(id: String, page: Int, filters: [String: Any] = [:]) async throws -> [String: Any] {
        let path = try buildSpiderPath(action: "category")
        var body: [String: Any] = ["id": id, "page": page]
        if !filters.isEmpty {
            body["filters"] = filters
        }
        return try await postJSON(path: path, port: spiderPort, body: body)
    }

    func getDetail(id: String) async throws -> [String: Any] {
        let path = try buildSpiderPath(action: "detail")
        return try await postJSON(path: path, port: spiderPort, body: ["id": id])
    }

    func getPlayUrl(flag: String, id: String) async throws -> [String: Any] {
        let path = try buildSpiderPath(action: "play")
        return try await postJSON(path: path, port: spiderPort, body: ["flag": flag, "id": id])
    }

    func search(wd: String, page: Int = 1) async throws -> [String: Any] {
        let path = try buildSpiderPath(action: "search")
        return try await postJSON(path: path, port: spiderPort, body: ["wd": wd, "page": page])
    }

    func searchWithSpider(keyword: String, spiderKey: String, spiderType: Int, apiBase: String, page: Int = 1) async throws -> [String: Any] {
        guard spiderPort > 0 else {
            throw SpiderError.nodeNotReady
        }
        let spiderPath: String
        if !apiBase.isEmpty {
            spiderPath = apiBase
        } else {
            spiderPath = "/\(spiderKey)/\(spiderType)"
        }

        let initPath = "\(spiderPath)/init"
        _ = try? await postJSON(path: initPath, port: spiderPort, body: [:])

        let searchPath = "\(spiderPath)/search"
        return try await postJSON(path: searchPath, port: spiderPort, body: ["wd": keyword, "page": page])
    }

    // MARK: - 源加载（通过managementPort）

    func loadSource(url urlString: String, completion: @escaping (Bool, String?) -> Void) {
        guard isNodeReady else {
            completion(false, "Node.js未就绪")
            return
        }

        let mPort = managementPort
        guard mPort > 0 else {
            completion(false, "Management端口未就绪")
            return
        }

        let path = "/source/loadPath"
        guard let url = URL(string: "http://127.0.0.1:\(mPort)\(path)") else {
            completion(false, "无效的URL")
            return
        }

        let body = ["path": urlString]
        guard let requestBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false, "请求体序列化失败")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody
        request.timeoutInterval = timeoutInterval

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "无效的响应")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(false, "HTTP错误: \(httpResponse.statusCode)")
                return
            }

            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let message = json["message"] as? String ?? json["error"] as? String
                completion(success, message)
            } else {
                completion(true, nil)
            }
        }
        task.resume()
    }
}
