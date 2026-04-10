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
        
        let spider = await ApiConfig.shared.spider
        
        let requestData: [String: Any] = [
            "action": "home",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "spider": spider
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建首页请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        Logger.shared.log("发送首页解析请求到 Node.js", level: .debug)
        let result = try await parseType3Source(sourceUrl: jsonString)
        
        Logger.shared.log("收到 Node.js 响应: \(result)", level: .debug)
        
        let success: Bool
        if let boolSuccess = result["success"] as? Bool {
            success = boolSuccess
        } else if let intSuccess = result["success"] as? Int {
            success = intSuccess != 0
        } else {
            Logger.shared.log("响应中缺少 success 字段或类型不正确", level: .error)
            throw SourceError.parseError("响应格式错误")
        }
        
        guard success else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            Logger.shared.log("Node.js 返回错误: \(errorMsg)", level: .error)
            throw SourceError.parseError(errorMsg)
        }
        
        guard let data = result["data"] as? [String: Any] else {
            Logger.shared.log("响应中 data 字段缺失或不是字典: \(String(describing: result["data"]))", level: .error)
            throw SourceError.parseError("数据格式错误")
        }
        
        var sorts: [MovieSort.SortData] = []
        var homeVideos: [Movie.Video] = []
        
        // 解析分类
        if let classList = data["class"] as? [[String: Any]] {
            for cls in classList {
                let id: String
                if let intId = cls["type_id"] as? Int {
                    id = String(intId)
                } else if let strId = cls["type_id"] as? String {
                    id = strId
                } else {
                    id = ""
                }
                let name = cls["type_name"] as? String ?? ""
                if !id.isEmpty && !name.isEmpty {
                    sorts.append(MovieSort.SortData(id: id, name: name))
                }
            }
            Logger.shared.log("解析到 \(sorts.count) 个分类", level: .info)
        } else {
            Logger.shared.log("data 中 class 字段不是数组，将使用默认分类", level: .warning)
        }
        
        // 解析视频列表（手动解析，宽容处理）
        if let list = data["list"] as? [[String: Any]] {
            for (index, item) in list.enumerated() {
                var video = Movie.Video()
                
                // 解析 vod_id
                if let intId = item["vod_id"] as? Int {
                    video.id = String(intId)
                } else if let strId = item["vod_id"] as? String {
                    video.id = strId
                } else {
                    Logger.shared.log("第 \(index) 个视频缺少 vod_id，跳过", level: .warning)
                    continue
                }
                
                // 解析 vod_name
                video.name = item["vod_name"] as? String ?? ""
                
                // 解析 vod_pic
                video.pic = item["vod_pic"] as? String ?? ""
                
                // 解析 vod_remarks
                video.note = item["vod_remarks"] as? String ?? ""
                
                // 解析其他可选字段
                video.year = item["vod_year"] as? String ?? ""
                video.area = item["vod_area"] as? String ?? ""
                video.type = item["type_name"] as? String ?? ""
                video.director = item["vod_director"] as? String ?? ""
                video.actor = item["vod_actor"] as? String ?? ""
                video.des = item["vod_content"] as? String ?? ""
                
                // 设置来源 key
                video.sourceKey = source.key
                
                homeVideos.append(video)
                Logger.shared.log("成功解析视频: \(video.name)", level: .debug)
            }
            Logger.shared.log("成功解析 \(homeVideos.count) 个首页视频", level: .info)
        } else {
            Logger.shared.log("data 中 list 字段不是数组: \(String(describing: data["list"]))", level: .warning)
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
        
        let spider = await ApiConfig.shared.spider
        
        let requestData: [String: Any] = [
            "action": "list",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "tid": sortId,
            "page": page,
            "filters": filters ?? [:],
            "spider": spider
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建分类列表请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        Logger.shared.log("收到 Node.js 响应: \(result)", level: .debug)
        
        let success: Bool
        if let boolSuccess = result["success"] as? Bool {
            success = boolSuccess
        } else if let intSuccess = result["success"] as? Int {
            success = intSuccess != 0
        } else {
            throw SourceError.parseError("响应格式错误")
        }
        
        guard success else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            throw SourceError.parseError(errorMsg)
        }
        
        guard let data = result["data"] as? [String: Any] else {
            throw SourceError.parseError("数据格式错误")
        }
        
        guard let list = data["list"] as? [[String: Any]] else {
            throw SourceError.parseError("list 字段不是数组")
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            var video = Movie.Video()
            
            if let intId = item["vod_id"] as? Int {
                video.id = String(intId)
            } else if let strId = item["vod_id"] as? String {
                video.id = strId
            } else {
                continue
            }
            
            video.name = item["vod_name"] as? String ?? ""
            video.pic = item["vod_pic"] as? String ?? ""
            video.note = item["vod_remarks"] as? String ?? ""
            video.year = item["vod_year"] as? String ?? ""
            video.area = item["vod_area"] as? String ?? ""
            video.type = item["type_name"] as? String ?? ""
            video.director = item["vod_director"] as? String ?? ""
            video.actor = item["vod_actor"] as? String ?? ""
            video.des = item["vod_content"] as? String ?? ""
            video.sourceKey = source.key
            
            videos.append(video)
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
        
        let spider = await ApiConfig.shared.spider
        
        let requestData: [String: Any] = [
            "action": "detail",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "vod_id": vodId,
            "spider": spider
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建详情请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        Logger.shared.log("收到 Node.js 响应: \(result)", level: .debug)
        
        let success: Bool
        if let boolSuccess = result["success"] as? Bool {
            success = boolSuccess
        } else if let intSuccess = result["success"] as? Int {
            success = intSuccess != 0
        } else {
            throw SourceError.parseError("响应格式错误")
        }
        
        guard success else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            throw SourceError.parseError(errorMsg)
        }
        
        guard let data = result["data"] as? [String: Any] else {
            throw SourceError.parseError("数据格式错误")
        }
        
        guard let list = data["list"] as? [[String: Any]],
              let first = list.first else {
            throw SourceError.parseError("详情数据为空")
        }
        
        var video = Movie.Video()
        if let intId = first["vod_id"] as? Int {
            video.id = String(intId)
        } else if let strId = first["vod_id"] as? String {
            video.id = strId
        } else {
            throw SourceError.parseError("缺少 vod_id")
        }
        
        video.name = first["vod_name"] as? String ?? ""
        video.pic = first["vod_pic"] as? String ?? ""
        video.note = first["vod_remarks"] as? String ?? ""
        video.year = first["vod_year"] as? String ?? ""
        video.area = first["vod_area"] as? String ?? ""
        video.type = first["type_name"] as? String ?? ""
        video.director = first["vod_director"] as? String ?? ""
        video.actor = first["vod_actor"] as? String ?? ""
        video.des = first["vod_content"] as? String ?? ""
        video.sourceKey = source.key
        
        let playFrom = first["vod_play_from"] as? String ?? ""
        let playUrl = first["vod_play_url"] as? String ?? ""
        
        Logger.shared.log("详情解析成功", level: .info)
        return VodInfo.from(video: video, playFrom: playFrom, playUrl: playUrl)
    }
    
    // MARK: - 搜索解析
    
    func parseSearch(from source: SourceBean, keyword: String) async throws -> [Movie.Video] {
        Logger.shared.log("开始搜索 (源: \(source.name), 关键词: \(keyword))", level: .info)
        
        let api = source.api
        guard !api.isEmpty else {
            Logger.shared.log("源 API 为空", level: .error)
            throw SourceError.emptyApi
        }
        
        let spider = await ApiConfig.shared.spider
        
        let requestData: [String: Any] = [
            "action": "search",
            "api": api,
            "key": source.key,
            "ext": source.ext ?? "",
            "wd": keyword,
            "spider": spider
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.shared.log("无法构建搜索请求数据", level: .error)
            throw SourceError.parseError("无法构建请求数据")
        }
        
        let result = try await parseType3Source(sourceUrl: jsonString)
        Logger.shared.log("收到 Node.js 响应: \(result)", level: .debug)
        
        let success: Bool
        if let boolSuccess = result["success"] as? Bool {
            success = boolSuccess
        } else if let intSuccess = result["success"] as? Int {
            success = intSuccess != 0
        } else {
            throw SourceError.parseError("响应格式错误")
        }
        
        guard success else {
            let errorMsg = result["error"] as? String ?? "解析失败"
            throw SourceError.parseError(errorMsg)
        }
        
        guard let data = result["data"] as? [String: Any] else {
            throw SourceError.parseError("数据格式错误")
        }
        
        guard let list = data["list"] as? [[String: Any]] else {
            throw SourceError.parseError("list 字段不是数组")
        }
        
        var videos: [Movie.Video] = []
        for item in list {
            var video = Movie.Video()
            
            if let intId = item["vod_id"] as? Int {
                video.id = String(intId)
            } else if let strId = item["vod_id"] as? String {
                video.id = strId
            } else {
                continue
            }
            
            video.name = item["vod_name"] as? String ?? ""
            video.pic = item["vod_pic"] as? String ?? ""
            video.note = item["vod_remarks"] as? String ?? ""
            video.year = item["vod_year"] as? String ?? ""
            video.area = item["vod_area"] as? String ?? ""
            video.type = item["type_name"] as? String ?? ""
            video.director = item["vod_director"] as? String ?? ""
            video.actor = item["vod_actor"] as? String ?? ""
            video.des = item["vod_content"] as? String ?? ""
            video.sourceKey = source.key
            
            videos.append(video)
        }
        
        Logger.shared.log("搜索到 \(videos.count) 个结果", level: .info)
        return videos
    }
}
