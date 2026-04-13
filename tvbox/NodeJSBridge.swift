import Foundation
import GCDWebServer
import NodeMobile  // 必须导入这个！

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    @Published var nodePort: Int?
    private var webServer: GCDWebServer?
    private var nodeHandle: UnsafeMutableRawPointer?
    
    private override init() {
        super.init()
    }
    
    func start() {
        // 启动原生HTTP服务，用于和Node通信
        startNativeServer()
        
        // 启动Node.js运行时
        startNodeRuntime()
    }
    
    private func startNativeServer() {
        webServer = GCDWebServer()
        
        // GCDWebServer 的正确 addHandler 用法
        webServer?.addHandler(
            forMethod: "POST",
            path: "/message",
            request: GCDWebServerRequest.self,
            processBlock: { [weak self] request in
                // 处理Node发来的消息
                if let body = request.body as Data?,
                   let message = String(data: body, encoding: .utf8) {
                    self?.handleNodeMessage(message)
                }
                
                return GCDWebServerResponse(statusCode: 200)
            }
        )
        
        // 启动服务，找一个可用的端口
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0, // 自动找端口
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            if let port = webServer?.port {
                Logger.shared.log("原生服务已启动，端口: \(port)", level: .info)
            }
        } catch {
            Logger.shared.log("启动原生服务失败: \(error)", level: .error)
        }
    }
    
    private func startNodeRuntime() {
        // 获取Node脚本的路径
        guard let nodeScriptPath = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "asset/js") else {
            Logger.shared.log("找不到Node脚本文件", level: .error)
            return
        }
        
        // NodeMobile 的正确用法
        let args = [nodeScriptPath]
        
        // 把 Swift 的 String 数组转成 C 的 char* 数组
        withUnsafeCStringArray(args) { cArgs in
            nodeHandle = nodeMobileStart(cArgs, Int32(args.count)) { message in
                // Node发来的消息回调
                if let message = message {
                    let str = String(cString: message)
                    DispatchQueue.main.async {
                        self.handleNodeMessage(str)
                    }
                }
            }
        }
        
        // 给Node发送run指令，加载源
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, let port = self.webServer?.port else { return }
            
            // 读取用户的网盘配置
            let diskConfig = self.loadDiskConfig()
            
            // 发送run指令
            let runMessage: [String: Any] = [
                "action": "run",
                "nativeServerPort": port,
                "path": nodeScriptPath,
                "diskConfig": [
                    "aliToken": diskConfig.aliToken,
                    "quarkCookie": diskConfig.quarkCookie,
                    "pan115Cookie": diskConfig.pan115Cookie,
                    "tianyiToken": diskConfig.tianyiToken,
                    "alistUrl": diskConfig.alistUrl,
                    "alistToken": diskConfig.alistToken
                ]
            ]
            
            self.sendMessageToNode(runMessage)
        }
    }
    
    // 辅助方法：把 Swift String 数组转成 C 字符串数组
    private func withUnsafeCStringArray(_ strings: [String], body: ([UnsafePointer<Int8>?]) throws -> Void) rethrows {
        try strings.withUnsafeBufferPointer { strBuffer in
            var cStrings: [UnsafePointer<Int8>?] = []
            for string in strings {
                try string.withCString { cStr in
                    cStrings.append(cStr)
                    try body(cStrings)
                }
            }
        }
    }
    
    private func handleNodeMessage(_ message: String) {
        // 解析Node发来的JSON消息
        guard let data = message.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let action = dict["action"] as? String {
            switch action {
            case "ready":
                Logger.shared.log("Node服务已就绪", level: .info)
                
            case "nodeServerPort":
                if let port = dict["port"] as? Int {
                    self.nodePort = port
                    Logger.shared.log("Node服务端口: \(port)", level: .info)
                }
                
            default:
                break
            }
        }
    }
    
    private func sendMessageToNode(_ message: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let str = String(data: data, encoding: .utf8) {
                str.withCString { cStr in
                    if let nodeHandle = nodeHandle {
                        nodeMobileSendMessage(nodeHandle, cStr)
                    }
                }
            }
        } catch {
            Logger.shared.log("发送消息给Node失败: \(error)", level: .error)
        }
    }
    
    /// 向Node服务发送请求，转发API调用
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard let port = nodePort else {
            throw NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node服务未启动"])
        }
        
        // 构建请求
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "NodeJSBridge", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Node服务请求失败"])
        }
        
        // 解析返回的JSON
        return try JSONSerialization.jsonObject(with: data)
    }
    
    // MARK: - 动态加载远程源
    func loadRemoteSource(path: String) {
        guard let port = webServer?.port else { return }
        
        // 读取用户的网盘配置
        let diskConfig = loadDiskConfig()
        
        // 发送run指令，加载远程源
        let runMessage: [String: Any] = [
            "action": "run",
            "nativeServerPort": port,
            "path": path,
            "diskConfig": [
                "aliToken": diskConfig.aliToken,
                "quarkCookie": diskConfig.quarkCookie,
                "pan115Cookie": diskConfig.pan115Cookie,
                "tianyiToken": diskConfig.tianyiToken,
                "alistUrl": diskConfig.alistUrl,
                "alistToken": diskConfig.alistToken
            ]
        ]
        
        sendMessageToNode(runMessage)
        Logger.shared.log("已加载远程Node源，路径: \(path)", level: .info)
    }
    
    // MARK: - 网盘配置
    func loadDiskConfig() -> DiskConfig {
        if let data = UserDefaults.standard.data(forKey: "DiskConfig") {
            do {
                return try JSONDecoder().decode(DiskConfig.self, from: data)
            } catch {
                Logger.shared.log("加载网盘配置失败: \(error)", level: .error)
            }
        }
        return DiskConfig()
    }
    
    func saveDiskConfig(_ config: DiskConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "DiskConfig")
            
            // 重新加载源，让新配置生效
            if let port = webServer?.port, let nodePath = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "asset/js") {
                let runMessage: [String: Any] = [
                    "action": "run",
                    "nativeServerPort": port,
                    "path": nodePath,
                    "diskConfig": [
                        "aliToken": config.aliToken,
                        "quarkCookie": config.quarkCookie,
                        "pan115Cookie": config.pan115Cookie,
                        "tianyiToken": config.tianyiToken,
                        "alistUrl": config.alistUrl,
                        "alistToken": config.alistToken
                    ]
                ]
                sendMessageToNode(runMessage)
            }
        } catch {
            Logger.shared.log("保存网盘配置失败: \(error)", level: .error)
        }
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
}
