import Foundation
import GCDWebServer

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    private var webServer: GCDWebServer?
    private var nodePort: UInt16 = 0
    private var nativePort: UInt16 = 0
    
    // 网盘配置
    private var diskConfig: DiskConfig = DiskConfig()
    
    override init() {
        super.init()
        loadDiskConfig()
    }
    
    // 启动原生HTTP服务
    func startNativeServer() {
        webServer = GCDWebServer()
        
        // 接收Node发来的消息
        webServer?.addPOSTHandler(forPath: "/message", asyncProcessBlock: { request, completion in
            do {
                let data = try Data(contentsOf: request.bodyData)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                
                if let action = json["action"] as? String {
                    switch action {
                    case "ready":
                        if let port = json["port"] as? UInt16 {
                            self.nodePort = port
                            print("Node服务已就绪，端口: \(port)")
                        }
                    default:
                        break
                    }
                }
                
                completion(GCDWebServerResponse(statusCode: 200))
            } catch {
                completion(GCDWebServerResponse(statusCode: 500))
            }
        })
        
        // 启动服务
        do {
            try webServer?.start(options: [
                GCDWebServerOption_Port: 0,
                GCDWebServerOption_BindToLocalhost: true
            ])
            nativePort = webServer?.port ?? 0
            print("原生服务已启动，端口: \(nativePort)")
        } catch {
            print("启动原生服务失败: \(error)")
        }
    }
    
    // 启动Node服务
    func startNodeService() {
        guard let resourcePath = Bundle.main.path(forResource: "nodejs-project", ofType: nil, inDirectory: "Resources") else {
            print("找不到Node资源目录")
            return
        }
        
        // 准备启动参数
        let args = [
            "node",
            resourcePath + "/index.js",
            "--native-port", String(nativePort)
        ]
        
        // 转换为C参数
        var cArgs = args.map { strdup($0) }
        cArgs.withUnsafeMutableBufferPointer { buffer in
            _ = node_start(Int32(args.count), buffer.baseAddress)
        }
        
        print("Node服务已启动")
    }
    
    // 给Node发送消息
    func sendMessageToNode(_ message: [String: Any]) {
        guard nodePort > 0 else {
            print("Node服务未就绪")
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
    func loadDefaultSource() {
        guard let resourcePath = Bundle.main.path(forResource: "nodejs-project", ofType: nil, inDirectory: "Resources") else {
            return
        }
        
        let message: [String: Any] = [
            "action": "run",
            "path": resourcePath,
            "config": diskConfig.toDictionary()
        ]
        
        sendMessageToNode(message)
    }
    
    // 加载远程源
    func loadRemoteSource(path: String) {
        let message: [String: Any] = [
            "action": "run",
            "path": path,
            "config": diskConfig.toDictionary()
        ]
        
        sendMessageToNode(message)
    }
    
    // 保存网盘配置
    func saveDiskConfig(_ config: DiskConfig) {
        self.diskConfig = config
        // 保存到本地
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "diskConfig")
        }
        // 重新加载源
        if let currentPath = NodeJSBridge.shared.currentSourcePath {
            loadRemoteSource(path: currentPath)
        } else {
            loadDefaultSource()
        }
    }
    
    // 加载网盘配置
    private func loadDiskConfig() {
        if let data = UserDefaults.standard.data(forKey: "diskConfig") {
            if let config = try? JSONDecoder().decode(DiskConfig.self, from: data) {
                self.diskConfig = config
            }
        }
    }
    
    // 当前源路径
    var currentSourcePath: String?
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
