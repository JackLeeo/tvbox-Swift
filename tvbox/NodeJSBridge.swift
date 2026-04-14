import Foundation
import GCDWebServer

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    private var webServer: GCDWebServer?
    private var nodePort: UInt16 = 0
    private var isNodeReady = false
    
    private var diskConfig: DiskConfig = DiskConfig()
    private var currentSourcePath: String?
    
    private override init() {
        super.init()
        loadConfig()
    }
    
    // MARK: - 配置管理
    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: "DiskConfig") {
            if let config = try? JSONDecoder().decode(DiskConfig.self, from: data) {
                self.diskConfig = config
            }
        }
    }
    
    func saveConfig(_ config: DiskConfig) {
        self.diskConfig = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "DiskConfig")
        }
        
        // 重新加载源
        if let path = currentSourcePath {
            loadSource(path: path)
        }
    }
    
    // MARK: - 启动服务
    func start() {
        startWebServer()
        startNode()
    }
    
    private func startWebServer() {
        webServer = GCDWebServer()
        
        // 处理Node的消息
        webServer?.addPOSTHandler(forPath: "/message", asyncProcessBlock: { request, completion in
            // 读取body
            guard let data = request.bodyData else {
                completion(GCDWebServerResponse(statusCode: 400))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.handleNodeMessage(json)
                }
                completion(GCDWebServerResponse(statusCode: 200))
            } catch {
                completion(GCDWebServerResponse(statusCode: 500))
            }
        })
        
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            if let port = webServer?.port {
                print("Native web server started on port: \(port)")
            }
        } catch {
            print("Failed to start web server: \(error)")
        }
    }
    
    private func startNode() {
        guard let resourcePath = Bundle.main.path(forResource: "nodejs-project/index", ofType: "js", inDirectory: "tvbox") else {
            print("Node script not found")
            return
        }
        
        let args: [String] = [
            "node",
            resourcePath,
            "--native-port", String(webServer?.port ?? 0)
        ]
        
        var argv = args.map { strdup($0) }
        
        _ = node_start(Int32(args.count), &argv)
        
        // 释放
        for arg in argv {
            free(arg)
        }
    }
    
    // MARK: - 处理Node消息
    private func handleNodeMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else {
            return
        }
        
        switch action {
        case "ready":
            if let port = message["port"] as? UInt16 {
                self.nodePort = port
                self.isNodeReady = true
                print("Node is ready on port: \(port)")
                
                // 加载默认源
                loadDefaultSource()
            }
            
        default:
            break
        }
    }
    
    // MARK: - 源加载
    private func loadDefaultSource() {
        if let defaultPath = Bundle.main.path(forResource: "nodejs-project", ofType: nil, inDirectory: "tvbox") {
            loadSource(path: defaultPath)
        }
    }
    
    func loadSource(path: String) {
        currentSourcePath = path
        
        guard isNodeReady else {
            return
        }
        
        // 发送run指令
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": diskConfig.toDictionary()
        ])
    }
    
    func loadRemoteSource(path: String) {
        loadSource(path: path)
    }
    
    // MARK: - 发送消息给Node
    private func sendMessageToNode(_ message: [String: Any]) {
        guard nodePort > 0 else {
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message, options: [])
            
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(nodePort)/message")!)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Failed to send message to node: \(error)")
                }
            }
            task.resume()
        } catch {
            print("Failed to serialize message: \(error)")
        }
    }
    
    // MARK: - 请求Node的API
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard nodePort > 0 else {
            throw NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node not ready"])
        }
        
        let url = URL(string: "http://127.0.0.1:\(nodePort)\(path)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "NodeJSBridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "Node API error"])
        }
        
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
}

// MARK: - 网盘配置
struct DiskConfig: Codable {
    var aliToken: String = ""
    var quarkCookie: String = ""
    var pan115Cookie: String = ""
    var tianyiToken: String = ""
    var alistUrl: String = ""
    var alistToken: String = ""
    var liveUrl: String = ""
    
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
