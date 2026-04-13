import Foundation
import ZIPFoundation

class SourceService {
    static let shared = SourceService()
    
    private var savedSources: [SourceBean] = []
    
    init() {
        loadSavedSources()
    }
    
    // MARK: - 远程源相关方法（我们之前加的）
    
    /// 解析Node源地址
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
    
    /// 下载远程Node源
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
    
    /// 保存源到本地
    func saveSource(_ source: SourceBean) {
        savedSources.append(source)
        do {
            let data = try JSONEncoder().encode(savedSources)
            UserDefaults.standard.set(data, forKey: "SavedSources")
        } catch {
            Logger.shared.log("保存源失败: \(error)", level: .error)
        }
    }
    
    /// 加载保存的源
    private func loadSavedSources() {
        if let data = UserDefaults.standard.data(forKey: "SavedSources") {
            do {
                savedSources = try JSONDecoder().decode([SourceBean].self, from: data)
            } catch {
                Logger.shared.log("加载保存的源失败: \(error)", level: .error)
            }
        }
    }
    
    /// 获取保存的源
    func getSavedSources() -> [SourceBean] {
        return savedSources
    }
    
    // MARK: - 搜索相关方法（修复后的，适配用户的类型）
    
    /// 全源搜索
    func searchAll(keyword: String) async throws -> [Movie.Video] {
        var allResults: [Movie.Video] = []
        
        // 遍历所有源进行搜索
        for source in ApiConfig.shared.sourceBeanList {
            do {
                let results = try await search(sourceBean: source, keyword: keyword)
                allResults.append(contentsOf: results)
            } catch {
                Logger.shared.log("搜索源 \(source.name) 失败: \(error)", level: .error)
                // 某个源搜索失败不影响其他源
                continue
            }
        }
        
        return allResults
    }
    
    /// 单个源搜索
    func search(sourceBean: sourceBean, keyword: String, page: Int = 1) async throws -> [Movie.Video] {
        // 判断是不是Node源
        if sourceBean.type == 3 { // Node源类型
            // 调用Node源的搜索接口
            let body: [String: Any] = [
                "wd": keyword,
                "page": page
            ]
            
            // 调用Node的API
            let response = try await NodeJSBridge.shared.requestNodeAPI(path: "/search", body: body)
            
            // 解析返回的数据
            if let responseDict = response as? [String: Any],
               let list = responseDict["list"] as? [[String: Any]] {
                
                // 把字典转换成Movie.Video
                var videos: [Movie.Video] = []
                for dict in list {
                    // 把字典转成JSON数据，然后用Movie.Video的解码器解码
                    // 因为Movie.Video已经有自定义的解码逻辑，正好适配Node源的字段
                    let jsonData = try JSONSerialization.data(withJSONObject: dict)
                    if let video = try? JSONDecoder().decode(Movie.Video.self, from: jsonData) {
                        // 设置sourceKey
                        var videoWithSource = video
                        videoWithSource.sourceKey = sourceBean.key
                        videos.append(videoWithSource)
                    }
                }
                
                return videos
            }
            
            return []
        } else {
            // 普通源，调用原来的NetworkManager的搜索方法
            // 这里用用户原来的NetworkManager的方法
            return try await NetworkManager.shared.search(sourceBean: sourceBean, keyword: keyword, page: page)
        }
    }
    
    // MARK: - Node源请求处理
    
    /// 请求Node源的API
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        return try await NodeJSBridge.shared.requestNodeAPI(path: path, body: body)
    }
}
