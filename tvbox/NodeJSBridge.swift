import Foundation
import UIKit

class NodeJSBridge: NSObject {
    static let shared = NodeJSBridge()
    
    // 状态标记
    private var isNodeReady = false
    private var pendingMessages: [String] = []
    
    // 回调映射，支持同时解析多个源
    private var pendingCompletions: [String: ([String: Any]?, Error?) -> Void] = [:]
    
    private var nodeScriptPath: String? {
        Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project")
    }
    
    private override init() {
        super.init()
        setupNodeEnvironment()
    }
    
    func setupNodeEnvironment() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self, let scriptPath = self.nodeScriptPath else {
                print("❌ Node 脚本路径不存在")
                return
            }
            
            // 启动参数
            let args = [scriptPath]
            let argc = args.count
            let argv = UnsafeMutablePointer<UnsafeMutablePointer<Int8>>.allocate(capacity: argc)
            
            for i in 0..<argc {
                argv[i] = strdup(args[i])
            }
            
            // 旧版 nodejs-mobile 启动函数，你的框架里有这个符号
            node_start(Int32(argc), argv)
            
            // 释放内存
            for i in 0..<argc {
                free(argv[i])
            }
            argv.deallocate()
        }
    }
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        let requestId = UUID().uuidString
        pendingCompletions[requestId] = completion
        
        // 构造请求数据
        let type3Data: [String: Any] = [
            "id": requestId,
            "type": 3,
            "url": sourceUrl,
            "headers": headers ?? [
                "User-Agent": "tvbox-Swift/1.0.0",
                "Referer": "https://tvbox.example.com"
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: type3Data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(nil, NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求数据"]))
            return
        }
        
        if isNodeReady {
            // Node 已就绪，直接发消息
            sendMessageToNode(jsonString)
        } else {
            // Node 还在启动，先缓存消息
            pendingMessages.append(jsonString)
        }
    }
    
    private func sendMessageToNode(_ message: String) {
        message.withCString { cStr in
            node_post_message(cStr)
        }
    }
    
    // Node 消息回调
    @objc func handleNodeMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard let data = message.data(using: .utf8),
                      let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                
                // 处理 Node 就绪通知
                if let status = result["status"] as? String, status == "nodejs_ready" {
                    self.isNodeReady = true
                    // 处理缓存的消息
                    for msg in self.pendingMessages {
                        self.sendMessageToNode(msg)
                    }
                    self.pendingMessages.removeAll()
                    return
                }
                
                // 处理解析结果，按请求ID匹配回调
                if let requestId = result["id"] as? String,
                   let completion = self.pendingCompletions.removeValue(forKey: requestId) {
                    if let success = result["success"] as? Bool, success {
                        completion(result["data"] as? [String: Any], nil)
                    } else {
                        let error = NSError(domain: "NodeJSBridge", code: -2, userInfo: [
                            NSLocalizedDescriptionKey: result["error"] as? String ?? "解析失败"
                        ])
                        completion(nil, error)
                    }
                }
            } catch {
                print("❌ 处理Node消息失败: \(error)")
            }
        }
    }
}

// MARK: - C 层回调
@_cdecl("node_message_handler")
func node_message_handler(message: UnsafePointer<CChar>) {
    let messageString = String(cString: message)
    NodeJSBridge.shared.handleNodeMessage(messageString)
}

// MARK: - 旧版 nodejs-mobile 函数声明（你的框架里有这些符号）
@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>)

@_silgen_name("node_post_message")
func node_post_message(_ message: UnsafePointer<CChar>)
