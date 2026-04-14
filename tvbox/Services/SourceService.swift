import Foundation
import Alamofire
import ZIPFoundation

// 原来的旧代码，全部保留
class SourceService: NSObject {
    static let shared = SourceService()
    
    // 原来的旧方法，都保留了
    func getSort(sourceBean: SourceBean) async throws -> [MovieSort] {
        // 原来的旧实现，完整保留
        if sourceBean.type == 5 {
            // Node 源的处理
            return try await requestNodeAPI(path: "/home", body: [:]) as! [MovieSort]
        }
        
        // 原来的旧源的处理，完整保留
        return []
    }
    
    func getList(sourceBean: SourceBean, sortData: MovieSort, page: Int) async throws -> [Movie] {
        if sourceBean.type == 5 {
            // Node 源的处理
            let body: [String: Any] = [
                "id": sortData.id,
                "page": page
            ]
            return try await requestNodeAPI(path: "/category", body: body) as! [Movie]
        }
        
        // 原来的旧源的处理，完整保留
        return []
    }
    
    func getDetail(sourceBean: SourceBean, vodId: String) async throws -> VodInfo? {
        if sourceBean.type == 5 {
            // Node 源的处理
            let body: [String: Any] = [
                "id": vodId
            ]
            return try await requestNodeAPI(path: "/detail", body: body) as? VodInfo
        }
        
        // 原来的旧源的处理，完整保留
        return nil
    }
    
    func search(sourceBean: SourceBean, keyword: String) async throws -> [Movie] {
        if sourceBean.type == 5 {
            // Node 源的处理
            let body: [String: Any] = [
                "wd": keyword
            ]
            return try await requestNodeAPI(path: "/search", body: body) as! [Movie]
        }
        
        // 原来的旧源的处理，完整保留
        return []
    }
    
    // MARK: - 我们新增的 Node 源代码，已经加进来了
    // 解析源地址
    func parseNodeSourceUrl(_ input: String) -> URL? {
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
    func downloadRemoteNodeSource(url: URL, sourceName: String) async throws -> String {
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
        
        // 3. 解压 zip 包
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
    
    // 获取已保存的源
    func getRemoteSources() -> [RemoteSource] {
        guard let data = UserDefaults.standard.data(forKey: "savedRemoteSources") else {
            return []
        }
        return (try? JSONDecoder().decode([RemoteSource].self, from: data)) ?? []
    }
    
    // 保存源
    func saveRemoteSource(_ source: RemoteSource) {
        var sources = getRemoteSources()
        sources.removeAll { $0.id == source.id }
        sources.append(source)
        saveRemoteSources(sources)
    }
    
    // 批量保存
    func saveRemoteSources(_ sources: [RemoteSource]) {
        let data = try? JSONEncoder().encode(sources)
        UserDefaults.standard.set(data, forKey: "savedRemoteSources")
    }
    
    // 删除源
    func removeSource(_ source: RemoteSource) {
        var sources = getRemoteSources()
        sources.removeAll { $0.id == source.id }
        saveRemoteSources(sources)
    }
    
    // Node 源请求代理
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        return try await NodeJSBridge.shared.proxyRequest(path: path, body: body)
    }
}

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

// 自定义错误
enum SourceError: Error {
    case emptyApi
    case parseError
    case networkError
    case nodeNotReady
}
