import Foundation
import GCDWebServer
import Combine

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    @Published var nodePort: Int?
    private var webServer: GCDWebServer?
    private var nodeThread: Thread?
    
    private override init() {
        super.init()
    }
    
    func start() {
        // 1. 启动原生 HTTP 服务，用于和 Node 双向通信
        startNativeServer()
        
        // 2. 启动 Node.js 线程
        startNodeThread()
    }
    
    private func startNativeServer() {
        webServer = GCDWebServer()
        
        webServer?.addHandler(
            forMethod: "POST",
            path: "/message",
            request: GCDWebServerDataRequest.self,
            processBlock: { [weak self] request in
                guard let self = self,
                      let dataRequest = request as? GCDWebServerDataRequest else {
                    return GCDWebServerResponse(statusCode: 400)
                }
                
                let body = dataRequest.data
                guard body.count > 0,
                      let message = String(data: body, encoding: .utf8) else {
                    return GCDWebServerResponse(statusCode: 400)
                }
                
                self.handleNodeMessage(message)
                return GCDWebServerResponse(statusCode: 200)
            }
        )
        
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            if let port = webServer?.port {
                Logger.shared.log("原生服务已启动，端口: \(port)", level: .info)
            }
        } catch {
            Logger.shared.log("启动原生服务失败: \(error)", level: .error)
        }
    }
    
    private func startNodeThread() {
        // 获取 Node 脚本路径
        guard let nodeScriptPath = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "asset/js") else {
            Logger.shared.log("找不到Node脚本文件", level: .error)
            return
        }
        
        // Node.js 的参数
        let args = [
            "node",
            nodeScriptPath,
            "--native-port", "\(webServer?.port ?? 0)"
        ]
        
        // 启动 Node.js 线程
        nodeThread = Thread { [weak self] in
            // 使用 strdup 简化内存管理
            var argv: [UnsafeMutablePointer<Int8>?] = args.map { strdup($0) }
            argv.append(nil)  // 以 NULL 结尾
            
            // 修复：在闭包中调用方法需要显式使用 self
            _ = self?.node_start(Int32(args.count), &argv)
            
            // 释放内存
            for ptr in argv {
                if let ptr = ptr {
                    free(ptr)
                }
            }
        }
        
        nodeThread?.start()
    }
    
    // 声明 node_start 函数
    @_silgen_name("_node_start")
    func node_start(_ argc: Int32, _ argv: UnsafePointer<UnsafeMutablePointer<Int8>?>?) -> Int32
    
    private func handleNodeMessage(_ message: String) {
        // 解析 Node 发来的消息
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
        // 直接发 HTTP 请求给 Node 的 HTTP 服务！
        guard let port = nodePort else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            
            // 修复URL：添加协议和主机
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/message")!)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let task = URLSession.shared.dataTask(with: request)
            task.resume()
        } catch {
            Logger.shared.log("发送消息给Node失败: \(error)", level: .error)
        }
    }
    
    /// 向 Node 服务发送请求
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard let port = nodePort else {
            throw NSError(domain: "NodeJSBridge", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Node服务未启动"])
        }
        
        // 修复URL：添加协议和主机
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "NodeJSBridge", code: httpResponse.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: "Node服务请求失败"])
        }
        
        // 解析返回的JSON
        return try JSONSerialization.jsonObject(with: data)
    }
    
    // MARK: - 动态加载源
    func loadRemoteSource(path: String) {
        // 给 Node 发送 run 指令，通过 HTTP
        sendMessageToNode([
            "action": "run",
            "path": path
        ])
        
        Logger.shared.log("已加载远程Node源，路径: \(path)", level: .info)
    }
    
    // MARK: - 网盘配置
    func saveDiskConfig(_ config: DiskConfig) {
        do {
            // 保存配置到本地
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "DiskConfig")
            
            // 把配置传给 Node，通过 HTTP
            sendMessageToNode([
                "action": "run",
                "diskConfig": [
                    "aliToken": config.aliToken,
                    "quarkCookie": config.quarkCookie,
                    "pan115Cookie": config.pan115Cookie,
                    "tianyiToken": config.tianyiToken,
                    "alistUrl": config.alistUrl,
                    "alistToken": config.alistToken
                ]
            ])
        } catch {
            Logger.shared.log("保存网盘配置失败: \(error)", level: .error)
        }
    }
    
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
