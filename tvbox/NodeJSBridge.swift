import Foundation
import NodeMobile
import GCDWebServer

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    private var nodePort: UInt16?
    private var nativeServer: GCDWebServer?
    private var nodeThread: Thread?
    
    private var diskConfig: DiskConfig = DiskConfig()
    
    override init() {
        super.init()
        loadDiskConfig()
    }
    
    func start() {
        // 启动原生本地服务
        startNativeServer()
        
        // 启动Node.js线程
        nodeThread = Thread(target: self, selector: #selector(startNode), object: nil)
        nodeThread?.start()
    }
    
    private func startNativeServer() {
        nativeServer = GCDWebServer()
        
        // 添加Node消息处理接口
        nativeServer?.addPOSTHandler(forPath: "/message", processBlock: { request, response, completion in
            // 读取请求体
            if let data = request.body as? Data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    self.handleNodeMessage(json)
                } catch {
                    Logger.shared.log("解析Node消息失败: \(error)", level: .error)
                }
            }
            
            completion(GCDWebServerResponse(statusCode: 200))
        })
        
        // 启动服务，随机端口
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
    
    @objc private func startNode() {
        // 准备Node.js的启动参数
        guard let jsPath = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "asset/js") else {
            Logger.shared.log("找不到Node.js脚本", level: .error)
            return
        }
        
        // 启动Node.js
        NodeRunner.run(jsPath) { [weak self] message in
            // 处理Node发来的消息
            self?.handleNodeMessageFromRunner(message)
        }
    }
    
    private func handleNodeMessage(_ message: [String: Any]?) {
        guard let message = message else { return }
        
        if let action = message["action"] as? String {
            switch action {
            case "ready":
                // Node环境就绪，发送native端口
                if let port = nativeServer?.port {
                    sendMessageToNode([
                        "action": "nativeServerPort",
                        "port": port
                    ])
                    
                    // 加载内置源
                    if let path = Bundle.main.path(forResource: "asset/js", ofType: nil) {
                        loadSource(path: path)
                    }
                }
                
            case "port":
                // Node服务端口
                if let port = message["port"] as? UInt16 {
                    self.nodePort = port
                    Logger.shared.log("Node服务已启动，端口: \(port)", level: .info)
                }
                
            default:
                break
            }
        }
    }
    
    private func handleNodeMessageFromRunner(_ message: String) {
        // 处理NodeRunner发来的消息
        do {
            let data = message.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            handleNodeMessage(json)
        } catch {
            Logger.shared.log("解析NodeRunner消息失败: \(error)", level: .error)
        }
    }
    
    func sendMessageToNode(_ message: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let str = String(data: data, encoding: .utf8)!
            NodeRunner.sendData(str)
        } catch {
            Logger.shared.log("发送消息到Node失败: \(error)", level: .error)
        }
    }
    
    func loadSource(path: String) {
        // 加载源，注入配置
        var config: [String: Any] = [:]
        config["aliToken"] = diskConfig.aliToken
        config["quarkCookie"] = diskConfig.quarkCookie
        config["pan115Cookie"] = diskConfig.pan115Cookie
        config["tianyiToken"] = diskConfig.tianyiToken
        config["alistUrl"] = diskConfig.alistUrl
        config["alistToken"] = diskConfig.alistToken
        
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": config
        ])
    }
    
    func loadRemoteSource(path: String) {
        // 加载远程源
        loadSource(path: path)
    }
    
    // MARK: - 网盘配置
    func loadDiskConfig() {
        if let data = UserDefaults.standard.data(forKey: "DiskConfig") {
            do {
                diskConfig = try JSONDecoder().decode(DiskConfig.self, from: data)
            } catch {
                Logger.shared.log("加载网盘配置失败: \(error)", level: .error)
            }
        }
    }
    
    func saveDiskConfig(_ config: DiskConfig) {
        diskConfig = config
        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "DiskConfig")
        } catch {
            Logger.shared.log("保存网盘配置失败: \(error)", level: .error)
        }
    }
    
    func getDiskConfig() -> DiskConfig {
        return diskConfig
    }
    
    // MARK: - 请求转发
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard let port = nodePort else {
            throw NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Node服务未启动"])
        }
        
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "NodeJSBridge", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Node请求失败"])
        }
        
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
}
