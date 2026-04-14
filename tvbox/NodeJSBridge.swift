import Foundation
import GCDWebServer

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    private var nativeServer: GCDWebServer?
    private var nodePort: UInt16 = 0
    private var isNodeRunning = false
    
    // 网盘配置
    private var diskConfig: [String: String] = [:]
    
    private override init() {
        super.init()
        loadDiskConfig()
    }
    
    // 启动原生 HTTP 服务
    func startNativeServer() {
        guard nativeServer == nil else { return }
        
        let server = GCDWebServer()
        
        // Node -> 原生 的通信接口
        server.addPOSTHandler(forPath: "/message", asyncProcessBlock: { request, completionBlock in
            // 处理 Node 发送过来的消息
            let data = request.bodyData  // 修复：使用正确的 bodyData 属性
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.handleNodeMessage(json)
            }
            completionBlock(GCDWebServerResponse(statusCode: 200), nil)
        })
        
        // 启动服务
        do {
            try server.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            self.nativeServer = server
            print("✅ 原生 HTTP 服务已启动，端口: \(server.port)")
        } catch {
            print("❌ 原生 HTTP 服务启动失败: \(error)")
        }
    }
    
    // 处理 Node 发送的消息
    private func handleNodeMessage(_ message: [String: Any]) {
        if let action = message["action"] as? String {
            switch action {
            case "ready":
                // Node 环境已就绪，发送 run 指令
                if let port = message["port"] as? UInt16 {
                    self.nodePort = port
                    self.loadDefaultSource()
                }
            default:
                break
            }
        }
    }
    
    // 给 Node 发送消息
    private func sendMessageToNode(_ message: [String: Any]) {
        guard nodePort > 0 else {
            print("❌ Node 服务未启动")
            return
        }
        
        let url = URL(string: "http://127.0.0.1:\(nodePort)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: message)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request)
        task.resume()
    }
    
    // 启动 Node.js 运行时
    func startNode() {
        guard !isNodeRunning else { return }
        
        startNativeServer()
        
        // 获取 Node 脚本路径
        guard let nodePath = Bundle.main.path(forResource: "nodejs-project/index", ofType: "js", inDirectory: nil) else {
            print("❌ 找不到 Node 脚本")
            return
        }
        
        // 准备参数
        let args = [
            "node",
            nodePath,
            "--native-port", String(nativeServer?.port ?? 0)
        ]
        
        // 转换为 C 字符串数组
        var argv = args.map { strdup($0) }
        
        // 启动 Node
        DispatchQueue.global().async {
            _ = node_start(Int32(args.count), &argv)
            print("Node 进程已退出")
            self.isNodeRunning = false
        }
        
        isNodeRunning = true
        print("✅ Node.js 运行时已启动")
    }
    
    // 加载默认源
    private func loadDefaultSource() {
        guard let defaultPath = Bundle.main.path(forResource: "nodejs-project", ofType: nil) else {
            return
        }
        
        sendMessageToNode([
            "action": "run",
            "path": defaultPath,
            "config": diskConfig
        ])
    }
    
    // 加载远程源
    func loadRemoteSource(path: String) {
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": diskConfig
        ])
    }
    
    // 加载网盘配置
    private func loadDiskConfig() {
        let defaults = UserDefaults.standard
        diskConfig = [
            "aliToken": defaults.string(forKey: "aliToken") ?? "",
            "quarkCookie": defaults.string(forKey: "quarkCookie") ?? "",
            "pan115Cookie": defaults.string(forKey: "pan115Cookie") ?? "",
            "tianyiToken": defaults.string(forKey: "tianyiToken") ?? "",
            "alistUrl": defaults.string(forKey: "alistUrl") ?? "",
            "alistToken": defaults.string(forKey: "alistToken") ?? "",
            "liveUrl": defaults.string(forKey: "liveUrl") ?? ""
        ]
    }
    
    // 保存网盘配置
    func saveDiskConfig(_ config: [String: String]) {
        let defaults = UserDefaults.standard
        for (key, value) in config {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        
        diskConfig = config
        
        // 重新加载源，让配置生效
        loadDefaultSource()
    }
    
    // 代理 Node 源的请求
    func proxyRequest(path: String, body: [String: Any]) async throws -> Any {
        guard nodePort > 0 else {
            throw NSError(domain: "NodeBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node 服务未启动"])
        }
        
        let url = URL(string: "http://127.0.0.1:\(nodePort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "NodeBridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "请求失败"])
        }
        
        return try JSONSerialization.jsonObject(with: data)
    }
}
