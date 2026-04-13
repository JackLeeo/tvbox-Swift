import Foundation
import ZIPFoundation

class SourceService {
    static let shared = SourceService()
    
    private var savedSources: [SourceBean] = []
    
    init() {
        loadSavedSources()
    }
    
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
    
    // MARK: - 首页分类接口
    func getSort(sourceBean: SourceBean) async throws -> [MovieSort.SortData] {
        // 调用Node的/home接口，获取分类配置
        let body: [String: Any] = [:]
        
        let result = try await NodeJSBridge.shared.requestNodeAPI(path: "/home", body: body)
        
        // 解析返回的分类数据
        // Node 返回的格式是: { class: [{ type_id: "1", type_name: "电影" }, ...] }
        if let dict = result as? [String: Any],
           let classList = dict["class"] as? [[String: Any]] {
            
            // 把字典转换成 MovieSort.SortData
            // Node 的字段是 type_id 和 type_name，我们需要映射到 SortData 的 id 和 name
            var mappedClassList: [[String: Any]] = []
            for item in classList {
                var mapped = item
                if let typeId = item["type_id"] as? String {
                    mapped["id"] = typeId
                }
                if let typeName = item["type_name"] as? String {
                    mapped["name"] = typeName
                }
                mappedClassList.append(mapped)
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: mappedClassList)
            let sorts = try JSONDecoder().decode([MovieSort.SortData].self, from: jsonData)
            
            return sorts
        }
        
        return []
    }
    
    // MARK: - 分类列表接口
    func getList(sourceBean: SourceBean, sortData: MovieSort.SortData, page: Int) async throws -> [Movie.Video] {
        // 调用Node的/category接口，获取分类影片列表
        // SortData 的 id 字段就是我们要传的 type_id
        let body: [String: Any] = [
            "id": sortData.id,  // 这里用 sortData.id，不是 typeId！
            "page": page
        ]
        
        let result = try await NodeJSBridge.shared.requestNodeAPI(path: "/category", body: body)
        
        // 解析返回的影片列表
        if let dict = result as? [String: Any],
           let list = dict["list"] as? [[String: Any]] {
            
            let jsonData = try JSONSerialization.data(withJSONObject: list)
            let videos = try JSONDecoder().decode([Movie.Video].self, from: jsonData)
            
            // 给每个video设置sourceKey
            return videos.map { video in
                var newVideo = video
                newVideo.sourceKey = sourceBean.key
                return newVideo
            }
        }
        
        return []
    }
    
    // MARK: - 搜索方法
    func search(sourceBean: SourceBean, keyword: String, page: Int = 1) async throws -> [Movie.Video] {
        // 调用Node的搜索接口
        let body: [String: Any] = [
            "wd": keyword,
            "page": page
        ]
        
        // 请求Node的API
        let result = try await NodeJSBridge.shared.requestNodeAPI(path: "/search", body: body)
        
        // 解析返回的数据，Node返回的是标准的CatVod格式
        if let dict = result as? [String: Any],
           let list = dict["list"] as? [[String: Any]] {
            
            // 把字典转换成JSON数据，然后用Movie.Video的解码器来解码
            let jsonData = try JSONSerialization.data(withJSONObject: list)
            let videos = try JSONDecoder().decode([Movie.Video].self, from: jsonData)
            
            // 给每个video设置sourceKey
            return videos.map { video in
                var newVideo = video
                newVideo.sourceKey = sourceBean.key
                return newVideo
            }
        }
        
        return []
    }
    
    /// 多源搜索，遍历所有源并行搜索，合并结果
    func searchAll(keyword: String) async throws -> [Movie.Video] {
        let allSources = await getAllSources()
        var allVideos: [Movie.Video] = []
        
        // 并行搜索所有源
        try await withThrowingTaskGroup(of: [Movie.Video].self) { group in
            for source in allSources {
                group.addTask {
                    do {
                        // 对每个源执行搜索
                        return try await self.search(sourceBean: source, keyword: keyword)
                    } catch {
                        Logger.shared.log("源 \(source.name) 搜索失败: \(error)", level: .error)
                        return []
                    }
                }
            }
            
            // 收集所有结果
            for try await videos in group {
                allVideos.append(contentsOf: videos)
            }
        }
        
        return allVideos
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
    
    // MARK: - 获取所有源（包含内置和已保存的）
    func getAllSources() async -> [SourceBean] {
        // 这里要加await，因为ApiConfig.shared.sourceBeanList是async属性
        let builtInSources = await ApiConfig.shared.sourceBeanList
        let remoteSources = getSavedSources()
        return builtInSources + remoteSources
    }
}
