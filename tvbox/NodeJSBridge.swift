import Foundation
import GCDWebServer

// 声明 NodeMobile 框架里的 C 函数
@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafePointer<UnsafeMutablePointer<Int8>?>?) -> Int32

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    var nativeServer: GCDWebServer?
    var nodePort: Int?
    var isNodeReady = false
    
    private override init() {
        super.init()
    }
    
    func start() {
        // 启动原生 HTTP 服务，用于和 Node 通信
        startNativeServer()
        
        // 启动 Node.js 运行时
        DispatchQueue.global().async {
            self.startNodeRuntime()
        }
    }
    
    private func startNativeServer() {
        nativeServer = GCDWebServer()
        
        // Swift 版本的 GCDWebServer API
        // 正确的 POST handler 方法
        nativeServer?.addPOSTHandler(forPath: "/message") { [weak self] request in
            guard let self = self else {
                return GCDWebServerResponse(statusCode: 500)
            }
            
            do {
                let data = try Data(contentsOf: request.body)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.handleNodeMessage(json)
                }
                return GCDWebServerResponse(statusCode: 200)
            } catch {
                Logger.shared.log("处理 Node 消息失败: \(error)", level: .error)
                return GCDWebServerResponse(statusCode: 500)
            }
        }
        
        // 启动服务，使用随机端口
        do {
            try nativeServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            if let port = nativeServer?.port {
                Logger.shared.log("原生服务已启动，端口: \(port)", level: .info)
            }
        } catch {
            Logger.shared.log("启动原生服务失败: \(error)", level: .error)
        }
    }
    
    private func handleNodeMessage(_ message: [String: Any]) {
        let action = message["action"] as? String ?? ""
        
        switch action {
        case "ready":
            // Node 环境已就绪，发送我们的端口给它
            if let nativePort = nativeServer?.port {
                sendMessageToNode([
                    "action": "nativeServerPort",
                    "port": nativePort
                ])
                
                // 加载默认源
                loadDefaultSource()
            }
            
        case "nodeServerPort":
            // Node 告诉我们它的服务端口
            if let port = message["port"] as? Int {
                nodePort = port
                isNodeReady = true
                Logger.shared.log("Node 服务已就绪，端口: \(port)", level: .info)
                
                // 通知 App Node 已就绪
                NotificationCenter.default.post(name: NSNotification.Name("NodeReady"), object: nil)
            }
            
        default:
            Logger.shared.log("未知的 Node 消息: \(action)", level: .warning)
        }
    }
    
    private func startNodeRuntime() {
        // 获取 Node 脚本的路径
        guard let scriptPath = Bundle.main.path(
            forResource: "index",
            ofType: "js",
            inDirectory: "nodejs-project"
        ) else {
            Logger.shared.log("找不到 Node 脚本文件", level: .error)
            return
        }
        
        // 准备 Node 的启动参数
        let args = [
            "node",
            scriptPath
        ]
        
        // 转换为 C 风格的参数
        let cArgs = args.map { $0.withCString { strdup($0) } }
        var argv = cArgs + [nil]  // 最后一个必须是 nil
        
        // 调用 node_start
        _ = node_start(Int32(args.count), &argv)
        
        // 释放内存
        cArgs.forEach { free($0) }
    }
    
    private func loadDefaultSource() {
        // 加载默认的内置源
        if let sourcePath = Bundle.main.path(forResource: nil, ofType: nil, inDirectory: "nodejs-project") {
            // 读取用户的网盘配置
            let diskConfig = DiskConfig.load()
            
            sendMessageToNode([
                "action": "run",
                "path": sourcePath,
                "config": diskConfig.toDictionary()
            ])
        }
    }
    
    func loadRemoteSource(path: String) {
        // 加载用户下载的远程源
        let diskConfig = DiskConfig.load()
        
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": diskConfig.toDictionary()
        ])
    }
    
    func sendMessageToNode(_ message: [String: Any]) {
        guard let nodePort = nodePort else {
            Logger.shared.log("Node 端口未就绪", level: .warning)
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(nodePort)/message")!)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let task = URLSession.shared.dataTask(with: request) { _, _, error in
                if let error = error {
                    Logger.shared.log("发送消息到 Node 失败: \(error)", level: .error)
                }
            }
            task.resume()
        } catch {
            Logger.shared.log("序列化消息失败: \(error)", level: .error)
        }
    }
    
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard let nodePort = nodePort, isNodeReady else {
            throw NSError(domain: "NodeBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node 服务未就绪"])
        }
        
        let url = URL(string: "http://127.0.0.1:\(nodePort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }
}

// 网盘配置模型
struct DiskConfig: Codable {
    var aliToken: String = ""
    var quarkCookie: String = ""
    var pan115Cookie: String = ""
    var tianyiToken: String = ""
    var alistUrl: String = ""
    var alistToken: String = ""
    var liveUrl: String = ""
    
    static func load() -> DiskConfig {
        guard let data = UserDefaults.standard.data(forKey: "DiskConfig") else {
            return DiskConfig()
        }
        do {
            return try JSONDecoder().decode(DiskConfig.self, from: data)
        } catch {
            return DiskConfig()
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: "DiskConfig")
        } catch {
            Logger.shared.log("保存配置失败: \(error)", level: .error)
        }
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "aliToken": aliToken,
            "quarkCookie": quarkCookie,
            "pan115Cookie": pan115Cookie,
            "tianyiToken": tianyiToken,
            "alistUrl": alistUrl,
            "alistToken": alistToken,
            "liveUrl": liveUrl
        ]
    }
}
