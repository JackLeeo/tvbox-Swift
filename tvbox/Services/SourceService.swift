import Foundation
import Alamofire
import ZIPFoundation

// 远程源模型
struct RemoteSource: Codable, Identifiable {
    let id: UUID
    let name: String
    let url: String
    let localPath: String
    let createTime: Date
    
    init(name: String, url: String, localPath: String) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.localPath = localPath
        self.createTime = Date()
    }
}

// 自定义错误类型
enum SourceError: Error {
    case emptyApi
    case parseError
    case networkError
    case nodeNotReady
}

class SourceService: NSObject {
    static let shared = SourceService()
    
    private var savedSources: [RemoteSource] = []
    
    private override init() {
        super.init()
        loadSavedSources()
    }
    
    // 解析源地址
    func parseSourceUrl(_ input: String) -> URL? {
        let input = input.trimmingWhitespace()
        
        // 普通 HTTP 地址
        if input.starts(with: "http://") || input.starts(with: "https://") {
            return URL(string: input)
        }
        
        // Gitee 私有仓库地址: gitee://token@gitee.com/user/repo/branch/path
        if input.starts(with: "gitee://") {
            let rest = String(input.dropFirst(8))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[rest.index(after: atIndex)...])
                
                // 解析 path: user/repo/branch/path
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let filePath = parts.dropFirst(3).joined(separator: "/")
                    
                    let apiUrl = "https://gitee.com/api/v5/repos/\(user)/\(repo)/contents/\(filePath)?ref=\(branch)"
                    var components = URLComponents(string: apiUrl)
                    components?.queryItems = [URLQueryItem(name: "access_token", value: token)]
                    return components?.url
                }
            }
        }
        
        // GitHub 私有仓库地址: github://token@github.com/user/repo/branch/path
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
                    let filePath = parts.dropFirst(3).joined(separator: "/")
                    
                    let apiUrl = "https://api.github.com/repos/\(user)/\(repo)/contents/\(filePath)?ref=\(branch)"
                    var components = URLComponents(string: apiUrl)
                    components?.queryItems = [URLQueryItem(name: "access_token", value: token)]
                    return components?.url
                }
            }
        }
        
        return nil
    }
    
    // 下载远程源
    func downloadRemoteSource(url: URL, sourceName: String) async throws -> String {
        // 1. 下载 zip 包
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // 2. 准备本地目录
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sourceDir = documentsDir.appendingPathComponent("sources/\(sourceName)")
        
        // 如果目录已存在，先删除
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            try FileManager.default.removeItem(at: sourceDir)
        }
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // 3. 解压 zip 包（修复 ZIPFoundation API 调用）
        let tempZipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        try data.write(to: tempZipURL)
        
        // 使用 ZIPFoundation 正确的 API
        try FileManager.default.unzipItem(at: tempZipURL, to: sourceDir)
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: tempZipURL)
        
        return sourceDir.path
    }
    
    // 保存源
    func saveSource(_ source: RemoteSource) {
        savedSources.append(source)
        saveToLocal()
    }
    
    // 删除源
    func removeSource(_ source: RemoteSource) {
        savedSources.removeAll { $0.id == source.id }
        // 删除本地文件
        try? FileManager.default.removeItem(atPath: source.localPath)
        saveToLocal()
    }
    
    // 获取已保存的源
    func getSavedSources() -> [RemoteSource] {
        return savedSources
    }
    
    // 本地持久化
    private func saveToLocal() {
        let data = try? JSONEncoder().encode(savedSources)
        UserDefaults.standard.set(data, forKey: "savedRemoteSources")
    }
    
    private func loadSavedSources() {
        guard let data = UserDefaults.standard.data(forKey: "savedRemoteSources") else {
            return
        }
        savedSources = (try? JSONDecoder().decode([RemoteSource].self, from: data)) ?? []
    }
    
    // Node 源请求代理
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        return try await NodeJSBridge.shared.proxyRequest(path: path, body: body)
    }
}
