import Foundation

class Type3SourceParser {
    static let shared = Type3SourceParser()
    private let nodeBridge = NodeJSBridge.shared
    
    // 初始化（启动 Node.js 环境）
    init() {
        nodeBridge.setupNodeEnvironment()
    }
    
    /// 解析 type=3 源
    /// - Parameters:
    ///   - sourceUrl: type=3 源的 URL（通常是远程 JS 脚本地址）
    ///   - completion: 解析结果回调（包含视频列表、分类等数据）
    func parseType3Source(sourceUrl: String, completion: @escaping ([String: Any]?, Error?) -> Void) {
        // 1. 构造 type=3 源数据（根据 tvbox 协议，type=3 通常包含 url 和 headers）
        let type3Data: [String: Any] = [
            "type": 3,
            "url": sourceUrl,
            "headers": [
                "User-Agent": "tvbox-Swift/1.0.0 (tvOS; 15.0)",
                "Referer": "https://tvbox.example.com"
            ]
        ]
        
        // 2. 设置回调并触发解析
        nodeBridge.parseCompletion = completion
        nodeBridge.parseType3Source(type3Data)
    }
}
