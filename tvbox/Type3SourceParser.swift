import Foundation

class Type3SourceParser {
    static let shared = Type3SourceParser()
    private let nodeBridge = NodeJSBridge.shared
    
    // MARK: - 通用解析方法
    
    /// 通用方法：向 Node.js 发送解析请求，返回原始字典
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers, completion: completion)
    }
    
    /// 通用方法：异步版本
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        try await nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers)
    }
    
    // MARK: - 首页解析
    
    /// 解析 jar 源的首页，返回分类列表和推荐视频
    func parseHome(from source: SourceBean) async throws -> (sorts: [MovieSort.SortData], homeVideos: [Movie.Video]) {
        let api = source.api
        guard !api.isEmpty else {
            throw SourceError.emptyApi
        }
        
        // 构建请求参数，传递源信息给 Node.js
        let requestData: [String: Any] = [
            "action": "home",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? ""
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SourceError.parseError("无法构建请求数据")
        }
        
        // 调用 Node.js 解析
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        // 解析返回数据
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any] else {
            throw SourceError.parseError(result["error"] as? String ?? "解析失败")
        }
        
        var sorts: [MovieSort.SortData] = []
        var homeVideos: [Movie.Video] = []
        
        // 解析分类
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
        }
        
        // 解析首页视频
        if let list = data["list"] as? [[String: Any]] {
            for item in list {
                if let itemData = try? JSONSerialization.data(withJSONObject: item),
                   var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                    video.sourceKey = source.key
                    homeVideos.append(video)
                }
            }
        }
        
        // 如果没有分类，添加一个默认的“首页”分类
        if sorts.isEmpty && !homeVideos.isEmpty {
            sorts = [MovieSort.SortData(id: "home", name: "首页")]
        }
        
        return (sorts, homeVideos)
    }
    
    // MARK: - 分类列表解析
    
    /// 解析分类下的视频列表
    func parseList(from source: SourceBean, sortId: String, page: Int = 1, filters: [String: String]? = nil) async throws -> [Movie.Video] {
        let api = source.api
        guard !api.isEmpty else {
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "list",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "tid": sortId,
            "page": page,
            "filters": filters ?? [:]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else {
            throw SourceError.parseError(result["error"] as? String ?? "解析失败")
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                video.sourceKey = source.key
                videos.append(video)
            }
        }
        
        return videos
    }
    
    // MARK: - 详情解析
    
    /// 解析视频详情
    func parseDetail(from source: SourceBean, vodId: String) async throws -> VodInfo? {
        let api = source.api
        guard !api.isEmpty else {
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "detail",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "vod_id": vodId
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]],
              let first = list.first else {
            throw SourceError.parseError(result["error"] as? String ?? "解析失败")
        }
        
        if let itemData = try? JSONSerialization.data(withJSONObject: first),
           var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
            video.sourceKey = source.key
            
            let playFrom = first["vod_play_from"] as? String ?? ""
            let playUrl = first["vod_play_url"] as? String ?? ""
            
            return VodInfo.from(video: video, playFrom: playFrom, playUrl: playUrl)
        }
        
        return nil
    }
    
    // MARK: - 搜索解析
    
    /// 在 jar 源中搜索
    func parseSearch(from source: SourceBean, keyword: String) async throws -> [Movie.Video] {
        let api = source.api
        guard !api.isEmpty else {
            throw SourceError.emptyApi
        }
        
        let requestData: [String: Any] = [
            "action": "search",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "wd": keyword
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        guard let success = result["success"] as? Bool, success,
              let data = result["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else {
            throw SourceError.parseError(result["error"] as? String ?? "解析失败")
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               var video = try? JSONDecoder().decode(Movie.Video.self, from: itemData) {
                video.sourceKey = source.key
                videos.append(video)
            }
        }
        
        return videos
    }
}
