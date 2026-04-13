import Foundation
import GCDWebServer
import NodeMobile

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    private var webServer: GCDWebServer?
    private var nodePort: UInt16?
    private var nodeThread: Thread?
    
    private override init() {
        super.init()
    }
    
    // MARK: - 启动服务
    func start() {
        // 启动原生HTTP服务
        startNativeServer()
        
        // 启动Node.js线程
        nodeThread = Thread(target: self, selector: #selector(startNode), object: nil)
        nodeThread?.start()
    }
    
    private func startNativeServer() {
        webServer = GCDWebServer()
        
        // 注册Node的端口通知接口
        webServer?.addPOSTHandler(forPath: "/notifyPort") { [weak self] request, query, body in
            if let data = body, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let port = json["port"] as? UInt16 {
                self?.nodePort = port
                Logger.shared.log("Node服务已启动，端口: \(port)", level: .info)
            }
            return .init(statusCode: 200, headers: nil, data: nil)
        }
        
        // 启动服务，使用随机端口
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            if let port = webServer?.port {
                Logger.shared.log("原生服务已启动，端口: \(port)", level: .info)
                // 保存端口，Node启动后会读取这个
                UserDefaults.standard.set(port, forKey: "NativeServerPort")
            }
        } catch {
            Logger.shared.log("启动原生服务失败: \(error)", level: .error)
        }
    }
    
    @objc private func startNode() {
        // 启动Node.js运行时
        let nodeDir = Bundle.main.path(forResource: "asset/js", ofType: nil, inDirectory: nil)!
        let entryPath = nodeDir.appending("/index.js")
        
        // 设置Node的工作目录
        FileManager.default.changeCurrentDirectoryPath(nodeDir)
        
        // 启动Node
        NodeMobile.start(withArguments: [entryPath])
    }
    
    // MARK: - 动态加载源
    func loadRemoteSource(path: String) {
        sendMessageToNode([
            "action": "run",
            "path": path
        ])
    }
    
    // MARK: - 网盘配置
    func saveDiskConfig(_ config: DiskConfig) {
        // 保存到本地
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "DiskConfig")
        }
        
        // 通知Node更新配置
        sendMessageToNode([
            "action": "updateConfig",
            "config": config.toDictionary()
        ])
    }
    
    func loadDiskConfig() -> DiskConfig {
        if let data = UserDefaults.standard.data(forKey: "DiskConfig"),
           let config = try? JSONDecoder().decode(DiskConfig.self, from: data) {
            return config
        }
        return DiskConfig()
    }
    
    // MARK: - 发送消息给Node
    private func sendMessageToNode(_ message: [String: Any]) {
        guard let port = nodePort else {
            Logger.shared.log("Node服务未启动，无法发送消息", level: .warning)
            return
        }
        
        guard let url = URL(string: "http://127.0.0.1:\(port)/message") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: message)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    // MARK: - 请求转发
    func forwardRequest(path: String, body: [String: Any]) async throws -> Any {
        guard let port = nodePort else {
            throw NSError(domain: "NodeBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node服务未启动"])
        }
        
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw NSError(domain: "NodeBridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效的请求地址"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }
}

// MARK: - 网盘配置模型
struct DiskConfig: Codable {
    var aliToken: String = ""
    var quarkCookie: String = ""
    var pan115Cookie: String = ""
    var tianyiToken: String = ""
    var alistUrl: String = ""
    var alistToken: String = ""
    
    func toDictionary() -> [String: String] {
        return [
            "aliToken": aliToken,
            "quarkCookie": quarkCookie,
            "pan115Cookie": pan115Cookie,
            "tianyiToken": tianyiToken,
            "alistUrl": alistUrl,
            "alistToken": alistToken
        ]
    }
}
