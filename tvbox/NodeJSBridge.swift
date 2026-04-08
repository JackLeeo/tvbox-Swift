import Foundation
import UIKit

class NodeJSBridge: NSObject {
    // 单例实例
    static let shared = NodeJSBridge()
    // Node.js 脚本路径（打包后从 Bundle 读取）
    private var nodeScriptPath: String {
        Bundle.main.path(forResource: "type3-parser", ofType: "js", inDirectory: "nodejs-project")!
    }
    // 解析结果回调
    var parseCompletion: (([String: Any]?, Error?) -> Void)?
    
    // 初始化 Node.js 环境（在子线程执行，避免阻塞主线程）
    func setupNodeEnvironment() {
        DispatchQueue.global().async {
            // 1. 设置 Node.js 运行参数（指定脚本路径）
            let args = [self.nodeScriptPath]
            let argc = args.count
            let argv = UnsafeMutablePointer<UnsafeMutablePointer<Int8>>.allocate(capacity: argc)
            
            for i in 0..<argc {
                argv[i] = strdup(args[i])
            }
            
            // 2. 初始化 Node.js 并执行脚本
            node_start(Int32(argc), argv)
            
            // 3. 释放内存
            for i in 0..<argc {
                free(argv[i])
            }
            argv.deallocate()
        }
    }
    
    // 传递 type=3 源数据给 Node.js 脚本
    func parseType3Source(_ sourceData: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: sourceData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            parseCompletion?(nil, NSError(domain: "NodeJSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 type=3 源数据"]))
            return
        }
        
        // 通过 Node.js 全局变量传递数据（需在脚本中监听）
        DispatchQueue.global().async {
            jsonString.withCString { node_post_message($0) }
        }
    }
    
    // Node.js 脚本回调结果处理（需暴露给 C 层）
    @objc func handleNodeMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let data = message.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                self?.parseCompletion?(nil, NSError(domain: "NodeJSBridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效的解析结果"]))
                return
            }
            self?.parseCompletion?(result, nil)
        }
    }
}

// MARK: - C 层回调绑定（Node.js 消息传递需 C 接口）
@_cdecl("node_message_handler")
func node_message_handler(message: UnsafePointer<CChar>) {
    let messageString = String(cString: message)
    NodeJSBridge.shared.handleNodeMessage(messageString)
}

// MARK: - Node.js 核心函数声明（来自 nodejs-mobile 静态库）
@_silgen_name("node_start")
func node_start(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>)

@_silgen_name("node_post_message")
func node_post_message(_ message: UnsafePointer<CChar>)
