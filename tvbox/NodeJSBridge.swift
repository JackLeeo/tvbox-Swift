import Foundation
import NodeMobile
import GCDWebServer

class NodeJSBridge: ObservableObject {
    static let shared = NodeJSBridge()
    
    /// Node服务的端口号
    @Published var nodePort: Int?
    
    /// 原生HTTP服务的端口号
    private var nativePort: Int?
    
    /// Node运行时的句柄
    private var nodeHandle: UnsafeMutableRawPointer?
    
    /// 原生HTTP服务
    private var webServer: GCDWebServer?
    
    /// 网盘配置
    @Published var diskConfig: DiskConfig?
    
    private init() {
        // 加载保存的配置
        loadDiskConfig()
    }
    
    // MARK: - 启动Node服务
    func start() {
        Logger.shared.log("正在启动Node.js服务...", level: .info)
        
        // 启动原生HTTP服务
        startNativeServer()
        
        // 启动Node运行时
        startNodeRuntime()
    }
    
    // MARK: - 启动原生HTTP服务
    private func startNativeServer() {
        webServer = GCDWebServer()
        
        // 添加消息处理接口，Node会通过这个接口给原生发消息
        webServer?.addPOSTHandler(forPath: "/message", requestBlock: { [weak self] request, path, query, body in
            guard let self = self,
                  let body = body as? Data,
                  let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return GCDWebServerResponse(statusCode: 400)
            }
            
            // 处理Node发来的消息
            self.handleNodeMessage(message)
            
            return GCDWebServerResponse(statusCode: 200)
        })
        
        // 启动服务，自动找可用端口
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            
            nativePort = Int(webServer?.port ?? 0)
            Logger.shared.log("原生HTTP服务已启动，端口: \(nativePort!)", level: .info)
        } catch {
            Logger.shared.log("原生HTTP服务启动失败: \(error)", level: .error)
        }
    }
    
    // MARK: - 启动Node运行时
    private func startNodeRuntime() {
        // 获取Node脚本的路径
        guard let scriptPath = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "asset/js") else {
            Logger.shared.log("找不到Node脚本文件", level: .error)
            return
        }
        
        // 准备Node的启动参数
        let args = [
            "node",
            scriptPath
        ]
        
        // 启动Node运行时
        nodeHandle = nodeMobileStart(args, args.count, { [weak self] message in
            // Node发来的消息会通过回调处理
            guard let self = self,
                  let data = message.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            self.handleNodeMessage(json)
        })
        
        Logger.shared.log("Node运行时已启动", level: .info)
    }
    
    // MARK: - 处理Node消息
    private func handleNodeMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        
        switch action {
        case "ready":
            // Node准备就绪，发送原生端口给Node
            if let port = nativePort {
                sendMessageToNode([
                    "action": "nativeServerPort",
                    "port": port
                ])
                
                // 发送run指令，加载默认源
                loadDefaultSource()
            }
            
        case "port":
            // Node服务的端口
            if let port = message["port"] as? Int {
                DispatchQueue.main.async {
                    self.nodePort = port
                }
                Logger.shared.log("Node服务已启动，端口: \(port)", level: .info)
            }
            
        default:
            Logger.shared.log("未知的Node消息: \(action)", level: .warning)
        }
    }
    
    // MARK: - 发送消息给Node
    private func sendMessageToNode(_ message: [String: Any]) {
        guard let nodeHandle = nodeHandle else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let str = String(data: data, encoding: .utf8) {
                nodeMobileSendMessage(nodeHandle, str)
            }
        } catch {
            Logger.shared.log("发送消息给Node失败: \(error)", level: .error)
        }
    }
    
    // MARK: - 加载默认源
    private func loadDefaultSource() {
        guard let defaultPath = Bundle.main.path(forResource: "", ofType: "", inDirectory: "asset/js") else {
            return
        }
        
        // 加载默认源，同时传入网盘配置
        let config = diskConfig ?? DiskConfig()
        loadSource(path: defaultPath, diskConfig: config)
    }
    
    // MARK: - 动态加载源
    func loadRemoteSource(path: String) {
        let config = diskConfig ?? DiskConfig()
        loadSource(path: path, diskConfig: config)
    }
    
    func loadSource(path: String, diskConfig: DiskConfig) {
        // 把网盘配置转成字典
        let configDict: [String: Any] = [
            "aliToken": diskConfig.aliToken,
            "quarkCookie": diskConfig.quarkCookie,
            "pan115Cookie": diskConfig.pan115Cookie,
            "tianyiToken": diskConfig.tianyiToken,
            "alistUrl": diskConfig.alistUrl,
            "alistToken": diskConfig.alistToken
        ]
        
        sendMessageToNode([
            "action": "run",
            "path": path,
            "config": configDict
        ])
        
        Logger.shared.log("已加载Node源，路径: \(path)", level: .info)
    }
    
    // MARK: - 请求转发到Node服务
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
    
    // MARK: - 网盘配置持久化
    func saveDiskConfig(_ config: DiskConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "DiskConfig")
            self.diskConfig = config
            
            // 如果Node已经启动，重新加载源以应用新配置
            if nodePort != nil {
                if let defaultPath = Bundle.main.path(forResource: "", ofType: "", inDirectory: "asset/js") {
                    loadSource(path: defaultPath, diskConfig: config)
                }
            }
        } catch {
            Logger.shared.log("保存网盘配置失败: \(error)", level: .error)
        }
    }
    
    func loadDiskConfig() {
        if let data = UserDefaults.standard.data(forKey: "DiskConfig") {
            do {
                diskConfig = try JSONDecoder().decode(DiskConfig.self, from: data)
            } catch {
                Logger.shared.log("加载网盘配置失败: \(error)", level: .error)
                diskConfig = DiskConfig()
            }
        } else {
            diskConfig = DiskConfig()
        }
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
}
