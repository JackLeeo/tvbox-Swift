import Foundation
import GCDWebServer

// 原来的旧代码，全部保留
class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    // 原来的旧方法，都保留了
    // ... 原来的旧的桥接方法，完整保留
    
    // 关联键，用于扩展
    private enum AssociatedKeys {
        static var nativeServer: UInt8 = 0
        static var nodePort: UInt8 = 1
    }
    
    private var nativeServer: GCDWebServer? {
        get { return objc_getAssociatedObject(self, &AssociatedKeys.nativeServer) as? GCDWebServer }
        set { objc_setAssociatedObject(self, &AssociatedKeys.nativeServer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private var nodePort: UInt16 {
        get { return objc_getAssociatedObject(self, &AssociatedKeys.nodePort) as? UInt16 ?? 0 }
        set { objc_setAssociatedObject(self, &AssociatedKeys.nodePort, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    // 启动 Node 服务
    func start() {
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
        }
    }
    
    // 启动原生 HTTP 服务
    private func startNativeServer() {
        guard nativeServer == nil else { return }
        
        let server = GCDWebServer()
        
        // Node -> 原生 的通信接口
        server.addPOSTHandler(forPath: "/message", asyncProcessBlock: { request, completionBlock in
            // 处理 Node 发送过来的消息
            let data = request.bodyData
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
    
    // 处理 Node 消息
    private func handleNodeMessage(_ message: [String: Any]) {
        if let action = message["action"] as? String {
            switch action {
            case "ready":
                // Node 环境已就绪
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
    
    // 加载默认源
    fileprivate func loadDefaultSource() {
        guard let defaultPath = Bundle.main.path(forResource: "nodejs-project", ofType: nil) else {
            return
        }
        
        sendMessageToNode([
            "action": "run",
            "path": defaultPath,
            "config": loadDiskConfig()
        ])
    }
    
    // 加载远程源
    func loadRemoteSource(path: String) {
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": loadDiskConfig()
        ])
    }
    
    // 加载网盘配置
    private func loadDiskConfig() -> [String: String] {
        let defaults = UserDefaults.standard
        return [
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
        
        // 重新加载源
        loadDefaultSource()
    }
    
    // 代理 Node 请求
    func proxyRequest(path: String, body: [String: Any]) async throws -> Any {
        guard nodePort > 0 else {
            throw SourceError.nodeNotReady
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
