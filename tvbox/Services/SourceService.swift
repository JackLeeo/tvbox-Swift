import Foundation
import ZIPFoundation

// MARK: - Remote Source Model
/// 远程 Node 源模型
struct RemoteSource: Codable, Identifiable {
    let id: String
    let name: String
    let url: String
    let localPath: String
    let createdAt: Date
    
    init(id: String = UUID().uuidString, name: String, url: String, localPath: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.localPath = localPath
        self.createdAt = createdAt
    }
}

/// 视频源数据服务 - 对应 Android 版 SourceViewModel.java
/// 负责从各视频源获取分类、列表、详情和搜索数据
class SourceService {
    static let shared = SourceService()
    
    private let network = NetworkManager.shared
    
    private init() {}
    
    // MARK: - Remote Node Source
    
    /// 解析远程源地址
    func parseNodeSourceUrl(_ input: String) -> (url: URL, type: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 解析 Gitee 私有仓库地址: gitee://token@gitee.com/user/repo/branch/path
        if trimmed.starts(with: "gitee://") {
            let rest = String(trimmed.dropFirst(8))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[rest.index(after: atIndex)...])
                
                // 解析 path: user/repo/branch/path
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let restPath = parts.dropFirst(3).joined(separator: "/")
                    
                    let apiPath = restPath.isEmpty ? "" : "/\(restPath)"
                    let urlStr = "https://\(token):x-oauth-basic@gitee.com/\(user)/\(repo)/releases/download/\(branch)\(apiPath)"
                    
                    if let url = URL(string: urlStr) {
                        return (url, "gitee")
                    }
                }
            }
        }
        
        // 解析 GitHub 私有仓库地址: github://token@github.com/user/repo/branch/path
        if trimmed.starts(with: "github://") {
            let rest = String(trimmed.dropFirst(9))
            if let atIndex = rest.firstIndex(of: "@") {
                let token = String(rest[..<atIndex])
                let path = String(rest[rest.index(after: atIndex)...])
                
                // 解析 path: user/repo/branch/path
                let parts = path.components(separatedBy: "/")
                if parts.count >= 3 {
                    let user = parts[0]
                    let repo = parts[1]
                    let branch = parts[2]
                    let restPath = parts.dropFirst(3).joined(separator: "/")
                    
                    let apiPath = restPath.isEmpty ? "" : "/\(restPath)"
                    let urlStr = "https://\(token)@raw.githubusercontent.com/\(user)/\(repo)/\(branch)\(apiPath)"
                    
                    if let url = URL(string: urlStr) {
                        return (url, "github")
                    }
                }
            }
        }
        
        // 普通 HTTP/HTTPS 地址
        if trimmed.isValidURL {
            if let url = URL(string: trimmed) {
                return (url, "http")
            }
        }
        
        return nil
    }
    
    /// 下载远程 Node 源
    func downloadRemoteNodeSource(url: URL, sourceName: String) async throws -> String {
        // 1. 下载远程文件
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // 2. 获取 Documents 目录
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sourceDir = documents.appendingPathComponent("sources").appendingPathComponent(sourceName)
        
        // 3. 如果是 zip 包，解压
        if url.pathExtension.lowercased() == "zip" {
            // 删除旧的
            try? FileManager.default.removeItem(at: sourceDir)
            
            // 解压
            try FileManager.default.unzipArchive(data: data, to: sourceDir)
        } else {
            // 普通文件，直接保存
            try? FileManager.default.removeItem(at: sourceDir)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            
            let fileURL = sourceDir.appendingPathComponent(url.lastPathComponent)
            try data.write(to: fileURL)
        }
        
        return sourceDir.path
    }
    
    /// 加载已保存的远程源
    func loadSavedRemoteSources() -> [RemoteSource] {
        if let data = UserDefaults.standard.data(forKey: "SavedRemoteSources") {
            do {
                return try JSONDecoder().decode([RemoteSource].self, from: data)
            } catch {
                Logger.shared.log("加载远程源失败: \(error)", level: .error)
                return []
            }
        }
        return []
    }
    
    /// 保存远程源
    func saveRemoteSources(_ sources: [RemoteSource]) {
        do {
            let data = try JSONEncoder().encode(sources)
            UserDefaults.standard.set(data, forKey: "SavedRemoteSources")
        } catch {
            Logger.shared.log("保存远程源失败: \(error)", level: .error)
        }
    }
    
    // MARK: - Node Source API
    
    /// 请求 Node 源的 API
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        return try await NodeJSBridge.shared.requestNodeAPI(path: path, body: body)
    }
    
    // MARK: - 获取分类列表
    
    /// 获取指定源的分类列表和首页推荐
    func getSort(sourceBean: SourceBean) async throws -> (sorts: [MovieSort.SortData], homeVideos: [Movie.Video]) {
        let api = sourceBean.api
        guard !api.isEmpty else {
            throw SourceError.emptyApi
        }
        
        // type=3 使用 Type3SourceParser 处理
        if sourceBean.type == 3 {
            return try await Type3SourceParser.shared.parseHome(from: sourceBean)
        }
        
        // 其他类型需要是 HTTP API
        guard sourceBean.isHttpApi else {
            throw SourceError.invalidApiUrl(api)
        }
        
        let jsonStr: String
        if sourceBean.type == 0 {
            // XML 接口
            jsonStr = try await network.getString(from: api)
        } else if sourceBean.type == 4 {
            // Type 4: 远程接口，需要 extend 和 filter 参数
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "filter", value: "true")
            ]
            // 加载 extend
            if let ext = sourceBean.ext, !ext.isEmpty {
                let extend = await resolveExtend(ext)
                if !extend.isEmpty {
                    queryItems.append(URLQueryItem(name: "extend", value: extend))
                }
            }
            let url = try buildURL(base: api, queryItems: queryItems)
            jsonStr = try await network.getString(from: url)
        } else {
            // JSON 接口 (type=1)
            let url = try buildURL(
                base: api,
                queryItems: [URLQueryItem(name: "ac", value: "class")]
            )
            jsonStr = try await network.getString(from: url)
        }
        
        var (sorts, homeVideos) = try parseSort(jsonStr, sourceBean: sourceBean)
        
        // 当大多数推荐视频的 vod_pic 为空时（ac=class 接口常见情况），
        // 额外请求列表接口获取带完整海报的推荐视频
        let picMissingCount = homeVideos.filter { $0.pic.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let needsFallback = homeVideos.isEmpty || picMissingCount > homeVideos.count / 2
        
        if needsFallback && (sourceBean.type == 1 || sourceBean.type == 4) {
            let listUrl: String
            if sourceBean.type == 4 {
                // type=4 用 ac=detail 格式，与 getList 保持一致
                let ext = Data("{}".utf8).base64EncodedString()
                listUrl = try buildURL(
                    base: api,
                    queryItems: [
                        URLQueryItem(name: "ac", value: "detail"),
                        URLQueryItem(name: "filter", value: "true"),
                        URLQueryItem(name: "pg", value: "1"),
                        URLQueryItem(name: "ext", value: ext)
                    ]
                )
            } else {
                // type=1 用 ac=videolist 格式
                listUrl = try buildURL(
                    base: api,
                    queryItems: [
                        URLQueryItem(name: "ac", value: "videolist"),
                        URLQueryItem(name: "pg", value: "1")
                    ]
                )
            }
            if let listStr = try? await network.getString(from: listUrl) {
                let fallback = (try? parseVideoList(listStr, sourceKey: sourceBean.key, type: sourceBean.type)) ?? []
                if !fallback.isEmpty {
                    homeVideos = fallback
                }
            }
        }
        
        return (sorts, homeVideos)
    }
    
    private func parseSort(_ jsonStr: String, sourceBean: SourceBean) throws -> (sorts: [MovieSort.SortData], homeVideos: [Movie.Video]) {
        guard let data = jsonStr.data(using: .utf8) else {
            throw SourceError.parseError("无法解析数据")
        }
        
        var sorts: [MovieSort.SortData] = []
        var homeVideos: [Movie.Video] = []
        
        if sourceBean.type == 0 {
            // XML 格式
            sorts = parseXMLCategories(from: jsonStr)
        } else {
            // JSON 格式 (type=1, type=4)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // 解析分类
                if let classList = json["class"] as? [[String: Any]] {
                    for cls in classList {
                        let id: String
                        if let intId = cls["type_id"] as? Int {
                            id = String(intId)
                        } else {
                            id = cls["type_id"] as? String ?? ""
                        }
                        let name = cls["type_name"] as? String ?? ""
                        sorts.append(MovieSort.SortData(id: id, name: name))
                    }
                }
                
                // 解析首页推荐视频
                if let list = json["list"] as? [[String: Any]] {
                    for item in list {
                        let decoder = JSONDecoder()
                        if let itemData = try? JSONSerialization.data(withJSONObject: item),
                           var video = try? decoder.decode(Movie.Video.self, from: itemData) {
                            video.sourceKey = sourceBean.key
                            homeVideos.append(video)
                        }
                    }
                }
            }
        }
        
        return (sorts, homeVideos)
    }
    
    private func parseXMLCategories(from xml: String) -> [MovieSort.SortData] {
        // 简化的 XML 分类解析
        var sorts: [MovieSort.SortData] = []
        let pattern = "<ty id=\"(\\d+)\"[^>]*>([^<]+)</ty>"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xml),
                   let nameRange = Range(match.range(at: 2), in: xml) {
                    let id = String(xml[idRange])
                    let name = String(xml[nameRange])
                    sorts.append(MovieSort.SortData(id: id, name: name))
                }
            }
        }
        return sorts
    }
    
    // MARK: - 获取分类视频列表
    
    /// 获取分类下的视频列表
    func getList(sourceBean: SourceBean, sortData: MovieSort.SortData, page: Int = 1, filters: [String: String]? = nil) async throws -> [Movie.Video] {
        let api = sourceBean.api
        guard !api.isEmpty else { throw SourceError.emptyApi }
        
        // type=3 使用 Type3SourceParser 处理
        if sourceBean.type == 3 {
            return try await Type3SourceParser.shared.parseList(
                from: sourceBean,
                sortId: sortData.id,
                page: page,
                filters: filters
            )
        }
        
        guard sourceBean.isHttpApi else { throw SourceError.invalidApiUrl(api) }
        
        let url: String
        if sourceBean.type == 0 {
            // XML 接口
            url = try buildURL(
                base: api,
                queryItems: [
                    URLQueryItem(name: "ac", value: "videolist"),
                    URLQueryItem(name: "t", value: sortData.id),
                    URLQueryItem(name: "pg", value: String(page))
                ]
            )
        } else if sourceBean.type == 4 {
            // Type 4: 远程接口
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "ac", value: "detail"),
                URLQueryItem(name: "filter", value: "true"),
                URLQueryItem(name: "t", value: sortData.id),
                URLQueryItem(name: "pg", value: String(page))
            ]
            
            // 附加筛选参数（base64 编码）
            if let filters = filters, !filters.isEmpty {
                if let filterData = try? JSONSerialization.data(withJSONObject: filters),
                   let filterStr = String(data: filterData, encoding: .utf8) {
                    let ext = Data(filterStr.utf8).base64EncodedString()
                    queryItems.append(URLQueryItem(name: "ext", value: ext))
                }
            } else {
                let ext = Data("{}".utf8).base64EncodedString()
                queryItems.append(URLQueryItem(name: "ext", value: ext))
            }
            
            // 加载 extend
            if let ext = sourceBean.ext, !ext.isEmpty {
                let extend = await resolveExtend(ext)
                if !extend.isEmpty {
                    queryItems.append(URLQueryItem(name: "extend", value: extend))
                }
            }
            url = try buildURL(base: api, queryItems: queryItems)
        } else {
            // JSON 接口 (type=1)
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "ac", value: "videolist"),
                URLQueryItem(name: "t", value: sortData.id),
                URLQueryItem(name: "pg", value: String(page))
            ]
            
            // 附加筛选参数
            if let filters = filters {
                for (key, value) in filters {
                    queryItems.append(URLQueryItem(name: key, value: value))
                }
            }
            url = try buildURL(base: api, queryItems: queryItems)
        }
        
        let jsonStr = try await network.getString(from: url)
        return try parseVideoList(jsonStr, sourceKey: sourceBean.key, type: sourceBean.type)
    }
    
    private func parseVideoList(_ jsonStr: String, sourceKey: String, type: Int) throws -> [Movie.Video] {
        guard let data = jsonStr.data(using: .utf8) else {
            throw SourceError.parseError("无法解析数据")
        }
        
        var videos: [Movie.Video] = []
        
        if type == 0 {
            videos = parseXMLVideoList(from: jsonStr, sourceKey: sourceKey)
        } else {
            // JSON 格式 (type=1, type=4)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["list"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                for item in list {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       var video = try? decoder.decode(Movie.Video.self, from: itemData) {
                        video.sourceKey = sourceKey
                        videos.append(video)
                    }
                }
            }
        }
        
        return videos
    }
    
    private func parseXMLVideoList(from xml: String, sourceKey: String) -> [Movie.Video] {
        // 简化 XML 视频列表解析
        var videos: [Movie.Video] = []
        let pattern = "<video>.*?<id>(\\d+)</id>.*?<name><!\\[CDATA\\[(.+?)\\]\\]></name>.*?<pic>(.*?)</pic>.*?<note><!\\[CDATA\\[(.*?)\\]\\]></note>.*?</video>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                var video = Movie.Video()
                if let r = Range(match.range(at: 1), in: xml) { video.id = String(xml[r]) }
                if let r = Range(match.range(at: 2), in: xml) { video.name = String(xml[r]) }
                if let r = Range(match.range(at: 3), in: xml) { video.pic = String(xml[r]) }
                if let r = Range(match.range(at: 4), in: xml) { video.note = String(xml[r]) }
                video.sourceKey = sourceKey
                videos.append(video)
            }
        }
        return videos
    }
    
    // MARK: - 获取详情
    
    /// 获取视频详情
    func getDetail(sourceBean: SourceBean, vodId: String) async throws -> VodInfo? {
        let api = sourceBean.api
        guard !api.isEmpty else { throw SourceError.emptyApi }
        
        // type=3 使用 Type3SourceParser 处理
        if sourceBean.type == 3 {
            return try await Type3SourceParser.shared.parseDetail(
                from: sourceBean,
                vodId: vodId
            )
        }
        
        guard sourceBean.isHttpApi else { throw SourceError.invalidApiUrl(api) }
        
        let url: String
        if sourceBean.type == 0 {
            url = try buildURL(
                base: api,
                queryItems: [
                    URLQueryItem(name: "ac", value: "videolist"),
                    URLQueryItem(name: "ids", value: vodId)
                ]
            )
        } else if sourceBean.type == 4 {
            // Type 4: 远程接口
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "ac", value: "detail"),
                URLQueryItem(name: "ids", value: vodId)
            ]
            
            // 加载 extend
            if let ext = sourceBean.ext, !ext.isEmpty {
                let extend = await resolveExtend(ext)
                if !extend.isEmpty {
                    queryItems.append(URLQueryItem(name: "extend", value: extend))
                }
            }
            url = try buildURL(base: api, queryItems: queryItems)
        } else {
            // JSON 接口 (type=1)
            url = try buildURL(
                base: api,
                queryItems: [
                    URLQueryItem(name: "ac", value: "detail"),
                    URLQueryItem(name: "ids", value: vodId)
                ]
            )
        }
        
        let jsonStr = try await network.getString(from: url)
        return try parseDetail(jsonStr, sourceKey: sourceBean.key, type: sourceBean.type)
    }
    
    private func parseDetail(_ jsonStr: String, sourceKey: String, type: Int) throws -> VodInfo? {
        if type == 0 {
            return parseXMLDetail(jsonStr, sourceKey: sourceKey)
        }
        
        guard let data = jsonStr.data(using: .utf8) else {
            throw SourceError.parseError("无法解析数据")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["list"] as? [[String: Any]],
           let first = list.first {
            
            let decoder = JSONDecoder()
            if let itemData = try? JSONSerialization.data(withJSONObject: first),
               var video = try? decoder.decode(Movie.Video.self, from: itemData) {
                video.sourceKey = sourceKey
                
                let playFrom = first["vod_play_from"] as? String ?? ""
                let playUrl = first["vod_play_url"] as? String ?? ""
                
                return VodInfo.from(video: video, playFrom: playFrom, playUrl: playUrl)
            }
        }
        
        return nil
    }
    
    // MARK: - 搜索
    
    /// 在指定源中搜索
    func search(sourceBean: SourceBean, keyword: String) async throws -> [Movie.Video] {
        let api = sourceBean.api
        guard !api.isEmpty else { throw SourceError.emptyApi }
        
        // type=3 使用 Type3SourceParser 处理
        if sourceBean.type == 3 {
            return try await Type3SourceParser.shared.parseSearch(
                from: sourceBean,
                keyword: keyword
            )
        }
        
        guard sourceBean.isHttpApi else { throw SourceError.invalidApiUrl(api) }
        
        let url: String
        if sourceBean.type == 0 {
            url = try buildURL(
                base: api,
                queryItems: [URLQueryItem(name: "wd", value: keyword)]
            )
        } else if sourceBean.type == 4 {
            // Type 4: 远程接口
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "wd", value: keyword)
            ]
            
            // 加载 extend
            if let ext = sourceBean.ext, !ext.isEmpty {
                let extend = await resolveExtend(ext)
                if !extend.isEmpty {
                    queryItems.append(URLQueryItem(name: "extend", value: extend))
                }
            }
            url = try buildURL(base: api, queryItems: queryItems)
        } else {
            // JSON 接口 (type=1)
            url = try buildURL(
                base: api,
                queryItems: [URLQueryItem(name: "wd", value: keyword)]
            )
        }
        
        let jsonStr = try await network.getString(from: url)
        return try parseVideoList(jsonStr, sourceKey: sourceKey, type: sourceBean.type)
    }
    
    // MARK: - 辅助方法
    
    private func buildURL(base: String, queryItems: [URLQueryItem]) throws -> String {
        guard var components = URLComponents(string: base) else {
            throw SourceError.invalidApiUrl(base)
        }
        components.queryItems = queryItems
        return components.url!.absoluteString
    }
    
    private func resolveExtend(_ ext: String) async -> String {
        // 简单的 extend 解析，支持 base64 解码
        if let data = Data(base64Encoded: ext) {
            return String(data: data, encoding: .utf8) ?? ext
        }
        return ext
    }
    
    func getRemoteSources() -> [RemoteSource] {
        return loadSavedRemoteSources()
    }
    
    func saveRemoteSource(name: String, url: String, localPath: String) async throws {
        var sources = loadSavedRemoteSources()
        // 移除同名的
        sources.removeAll { $0.name == name }
        // 添加新的
        sources.append(RemoteSource(name: name, url: url, localPath: localPath))
        // 保存
        saveRemoteSources(sources)
    }
}
