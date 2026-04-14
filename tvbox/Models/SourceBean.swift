import Foundation

struct SourceBean: Codable, Identifiable {
    let id: UUID
    let name: String
    let api: String
    var type: Int  // 1=旧源, 5=Node源
    var localPath: String?  // Node源的本地路径
    
    // 原来的旧属性，全部保留
    var group: String?
    var isChecked: Bool = false
    
    init(name: String, api: String, type: Int = 0, localPath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.api = api
        self.type = type
        self.localPath = localPath
    }
    
    // 原来的旧方法，全部保留
    enum CodingKeys: String, CodingKey {
        case id, name, api, type, localPath, group, isChecked
    }
}

// 源地址解析工具
struct SourceUrlParser {
    static func parse(_ input: String) -> (url: URL, type: String)? {
        let input = input.trimmingWhitespace()
        
        // 解析Gitee地址
        if input.starts(with: "gitee://") {
            let rest = String(input.dropFirst(8))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[rest.index(after: atIndex)...])
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let filePath = parts.count > 3 ? parts[3...].joined(separator: "/") : ""
                    let apiUrl = URL(string: "https://gitee.com/api/v5/repos/\(user)/\(repo)/contents/\(filePath)?ref=\(branch)")!
                    return (apiUrl, "gitee")
                }
            }
        }
        
        // 解析GitHub地址
        if input.starts(with: "github://") {
            let rest = String(input.dropFirst(9))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[rest.index(after: atIndex)...])
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let filePath = parts.count > 3 ? parts[3...].joined(separator: "/") : ""
                    let apiUrl = URL(string: "https://api.github.com/repos/\(user)/\(repo)/contents/\(filePath)?ref=\(branch)")!
                    return (apiUrl, "github")
                }
            }
        }
        
        // 普通HTTP地址
        if let url = URL(string: input), url.scheme == "http" || url.scheme == "https" {
            return (url, "http")
        }
        
        return nil
    }
}
