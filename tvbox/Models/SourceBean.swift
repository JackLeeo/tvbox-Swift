import Foundation

struct SourceBean: Codable, Identifiable {
    let id: UUID
    let name: String
    let url: String
    let type: Int
    var localPath: String?
    var isNodeSource: Bool {
        return type == 5
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, type, localPath
    }
    
    init(name: String, url: String, type: Int) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.type = type
        self.localPath = nil
    }
    
    func parseNodeSourceUrl() -> (url: URL, type: String)? {
        let input = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 解析Gitee地址
        if input.starts(with: "gitee://") {
            let pattern = "gitee://([^@]+)@gitee\\.com/([^/]+)/([^/]+)/([^/]+)/(.+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
                
                let token = (input as NSString).substring(with: match.range(at: 1))
                let user = (input as NSString).substring(with: match.range(at: 2))
                let repo = (input as NSString).substring(with: match.range(at: 3))
                let branch = (input as NSString).substring(with: match.range(at: 4))
                let path = (input as NSString).substring(with: match.range(at: 5))
                
                let apiUrl = "https://gitee.com/api/v5/repos/\(user)/\(repo)/contents/\(path)?ref=\(branch)"
                if let url = URL(string: apiUrl) {
                    return (url, "gitee")
                }
            }
        }
        
        // 解析GitHub地址
        if input.starts(with: "github://") {
            let pattern = "github://([^@]+)@github\\.com/([^/]+)/([^/]+)/([^/]+)/(.+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
                
                let token = (input as NSString).substring(with: match.range(at: 1))
                let user = (input as NSString).substring(with: match.range(at: 2))
                let repo = (input as NSString).substring(with: match.range(at: 3))
                let branch = (input as NSString).substring(with: match.range(at: 4))
                let path = (input as NSString).substring(with: match.range(at: 5))
                
                let apiUrl = "https://api.github.com/repos/\(user)/\(repo)/contents/\(path)?ref=\(branch)"
                if let url = URL(string: apiUrl) {
                    return (url, "github")
                }
            }
        }
        
        // 普通HTTP地址
        if input.starts(with: "http://") || input.starts(with: "https://") {
            if let url = URL(string: input) {
                return (url, "http")
            }
        }
        
        return nil
    }
}
