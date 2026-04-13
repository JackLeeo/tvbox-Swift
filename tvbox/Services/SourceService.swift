import Foundation
import ZIPFoundation

class SourceService {
    static let shared = SourceService()
    
    private var savedSources: [SourceBean] = []
    
    init() {
        loadSavedSources()
    }
    
    // MARK: - 原有搜索方法（保留原来的）
    func searchAll(keyword: String) async -> [VodInfo] {
        // 原来的全源搜索逻辑，保留不变
        var allVideos: [VodInfo] = []
        for source in ApiConfig.shared.sourceBeanList {
            do {
                let videos = try await search(sourceBean: source, keyword: keyword)
                allVideos.append(contentsOf: videos)
            } catch {
                continue
            }
        }
        return allVideos
    }
    
    func search(sourceBean: SourceBean, keyword: String) async throws -> [VodInfo] {
        // 原来的单源搜索逻辑，保留不变
        if sourceBean.type == 3 {
            // Node源的搜索，转发到Node服务
            let result = try await NodeJSBridge.shared.forwardRequest(
                path: "/search",
                body: ["wd": keyword, "page": 1]
            )
            if let dict = result as? [String: Any],
               let list = dict["list"] as? [[String: Any]] {
                return list.map { VodInfo.from(dict: $0) }
            }
            return []
        } else {
            // 原来的普通源搜索逻辑，保留不变
            return try await NetworkManager.shared.search(sourceBean: sourceBean, keyword: keyword)
        }
    }
    
    // MARK: - 新增的远程源方法（我们加的）
    // MARK: - 源地址解析
    func parseNodeSourceUrl(_ input: String) -> (url: URL, type: String)? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 解析Gitee私有地址
        if input.starts(with: "gitee://") {
            let rest = String(input.dropFirst(8))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[atIndex...].dropFirst())
                
                // 解析路径: user/repo/branch/path
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let filePath = parts.dropFirst(3).joined(separator: "/")
                    
                    let url = URL(string: "https://\(token)@gitee.com/\(user)/\(repo)/raw/\(branch)/\(filePath)")!
                    return (url, "gitee")
                }
            }
        }
        
        // 解析GitHub私有地址
        if input.starts(with: "github://") {
            let rest = String(input.dropFirst(9))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[atIndex...].dropFirst())
                
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let filePath = parts.dropFirst(3).joined(separator: "/")
                    
                    let url = URL(string: "https://\(token)@raw.githubusercontent.com/\(user)/\(repo)/\(branch)/\(filePath)")!
                    return (url, "github")
                }
            }
        }
        
        // 普通HTTP地址
        if let url = URL(string: input), url.scheme == "http" || url.scheme == "https" {
            return (url, "http")
        }
        
        return nil
    }
    
    // MARK: - 远程源下载
    func downloadRemoteNodeSource(url: URL, sourceName: String) async throws -> String {
        // 下载文件
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // 保存到Documents目录
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sourceDir = docsDir.appendingPathComponent("sources/\(sourceName)")
        
        // 如果目录已存在，先删除
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            try FileManager.default.removeItem(at: sourceDir)
        }
        
        // 创建目录
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // 解压zip包
        if url.pathExtension == "zip" {
            let tempZip = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: sourceDir, create: true).appendingPathComponent("temp.zip")
            try data.write(to: tempZip)
            
            try FileManager.default.unzipItem(at: tempZip, to: sourceDir)
            try FileManager.default.removeItem(at: tempZip)
        } else {
            // 直接保存文件
            try data.write(to: sourceDir.appendingPathComponent(url.lastPathComponent))
        }
        
        return sourceDir.path
    }
    
    // MARK: - 源的持久化
    private func loadSavedSources() {
        if let data = UserDefaults.standard.data(forKey: "SavedSources") {
            do {
                savedSources = try JSONDecoder().decode([SourceBean].self, from: data)
            } catch {
                Logger.shared.log("加载保存的源失败: \(error)", level: .error)
            }
        }
    }
    
    func saveSource(_ source: SourceBean) {
        savedSources.append(source)
        do {
            let data = try JSONEncoder().encode(savedSources)
            UserDefaults.standard.set(data, forKey: "SavedSources")
        } catch {
            Logger.shared.log("保存源失败: \(error)", level: .error)
        }
    }
    
    func getSavedSources() -> [SourceBean] {
        return savedSources
    }
}
