import Foundation

class Type3SourceParser {
    static let shared = Type3SourceParser()
    private let nodeBridge = NodeJSBridge.shared
    
    // MARK: - 通用解析方法
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        Logger.shared.log("Type3SourceParser 通用解析请求", level: .debug)
        nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers, completion: completion)
    }
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        Logger.shared.log("Type3SourceParser 异步通用解析", level: .debug)
        return try await nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers)
    }
    
    // MARK: - 首页解析
    
    func parseHome(from source: SourceBean) async throws -> (sorts: [MovieSort.SortData], homeVideos: [Movie.Video]) {
        Logger.shared.log("开始解析首页 (源: \(source.name), type=\(source.type))", level: .info)
        
        let api = source.api
        guard !api.isEmpty else {
            Logger.shared.log("源 API 为空", level: .error)
            throw SourceError.emptyApi
        }
        
        // 对于 jar 源，需要传递完整信息，包括 ext 和 jar 字段
        let requestData: [String: Any] = [
            "action": "home",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "jar": source.jar ?? ""
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建首页请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        Logger.shared.log("发送首页解析请求到 Node.js", level: .debug)
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any] else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            Logger.shared.log("首页解析失败: \(errorMsg)", level: .error)
            throw SourceError.parseError(errorMsg)
        }
        
        var sorts: [MovieSort.SortData] = []
        var homeVideos: [Movie.Video] = []
        
        if let classList = data["class"] as? [[String: Any]] {
            for cls in classList {
                let id: String
                if let intId = cls["type_id"] as? Int {
                    id = String(intId)
                } else {
                    id = cls["type_id"] as? String ?? ""
                }
                let name = cls["type_name"] as? String ?? ""
                if !id.isEmpty && !name.isEmpty {
                    sorts.append(MovieSort.SortData(id: id, name: name))
                }
            }
            Logger.shared.log("解析到 \(sorts.count) 个分类", level: .info)
        }
        
        if let list = data["list"] as? [[String: Any]] {
            for item in list {
                if let itemData = try? JSONSerialization.data(withJSONObject: item),
                   var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                    video.sourceKey = source.key
                    homeVideos.append(video)
                }
            }
            Logger.shared.log("解析到 \(homeVideos.count) 个首页视频", level: .info)
        }
        
        if sorts.isEmpty && !homeVideos.isEmpty {
            sorts = [MovieSort.SortData(id: "home", name: "首页")]
            Logger.shared.log("未返回分类，使用默认'首页'分类", level: .info)
        }
        
        return (sorts, homeVideos)
    }
    
    // MARK: - 分类列表解析
    
    func parseList(from source: SourceBean, sortId: String, page: Int = 1, filters: [String: String]? = nil) async throws -> [Movie.Video] {
        Logger.shared.log("开始解析分类列表 (源: \(source.name), 分类ID: \(sortId), 页码: \(page))", level: .info)
        
        let api = source.api
        guard !api.isEmpty else {
            Logger.shared.log("源 API 为空", level: .error)
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "list",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "jar": source.jar ?? "",
            "tid": sortId,
            "page": page,
            "filters": filters ?? [:]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建分类列表请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            Logger.shared.log("分类列表解析失败: \(errorMsg)", level: .error)
            throw SourceError.parseError(errorMsg)
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                video.sourceKey = source.key
                videos.append(video)
            }
        }
        
        Logger.shared.log("解析到 \(videos.count) 个视频", level: .info)
        return videos
    }
    
    // MARK: - 详情解析
    
    func parseDetail(from source: SourceBean, vodId: String) async throws -> VodInfo? {
        Logger.shared.log("开始解析详情 (源: \(source.name), vodId: \(vodId))", level: .info)
        
        let api = source.api
        guard !api.isEmpty else {
            Logger.shared.log("源 API 为空", level: .error)
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "detail",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "jar": source.jar ?? "",
            "vod_id": vodId
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建详情请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]],
              let first = list.first else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            Logger.shared.log("详情解析失败: \(errorMsg)", level: .error)
            throw SourceError.parseError(errorMsg)
        }
        
        if let itemData = try? JSONSerialization.data(withJSONObject: first),
           var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
            video.sourceKey = source.key
            
            let playFrom = first["vod_play_from"] as? String ?? ""
            let playUrl = first["vod_play_url"] as? String ?? ""
            
            Logger.shared.log("详情解析成功，播放线路数: \(playFrom.split(separator: "$$$").count)", level: .info)
            return VodInfo.from(video: video, playFrom: playFrom, playUrl: playUrl)
        }
        
        Logger.shared.log("详情数据无法转换为 VodInfo", level: .warning)
        return nil
    }
    
    // MARK: - 搜索解析
    
    func parseSearch(from source: SourceBean, keyword: String) async throws -> [Movie.Video] {
        Logger.shared.log("开始搜索 (源: \(source.name), 关键词: \(keyword))", level: .info)
        
        let api = source.api
        guard !api.isEmpty else {
            Logger.shared.log("源 API 为空", level: .error)
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "search",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "jar": source.jar ?? "",
            "wd": keyword
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建搜索请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            Logger.shared.log("搜索解析失败: \(errorMsg)", level: .error)
            throw SourceError.parseError(errorMsg)
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                video.sourceKey = source.key
                videos.append(video)
            }
        }
        
        Logger.shared.log("搜索到 \(videos.count) 个结果", level: .info)
        return videos
    }
}
