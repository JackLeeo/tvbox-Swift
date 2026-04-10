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
            Logger.shared.log("data 中 class 字段不是数组: \(String(describing: data["class"]))", level: .warning)
        }
        
        if let list = data["list"] as? [[String: Any]] {
            for (index, item) in list.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: item)
                    let decoder = JSONDecoder()
                    var video = try decoder.decode(Movie.Video.self, from: itemData)
                    video.sourceKey = source.key
                    homeVideos.append(video)
                } catch {
                    Logger.shared.log("解码第 \(index) 个视频条目失败: \(error)", level: .error)
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            Logger.shared.log("  缺失字段: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                        case .typeMismatch(let type, let context):
                            Logger.shared.log("  类型不匹配: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                        case .valueNotFound(let type, let context):
                            Logger.shared.log("  值为空: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                        case .dataCorrupted(let context):
                            Logger.shared.log("  数据损坏: \(context.debugDescription)", level: .error)
                        @unknown default:
                            Logger.shared.log("  未知解码错误", level: .error)
                        }
                    }
                    Logger.shared.log("  原始数据: \(item)", level: .debug)
                }
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
        for (index, item) in list.enumerated() {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: item)
                let decoder = JSONDecoder()
                var video = try decoder.decode(Movie.Video.self, from: itemData)
                video.sourceKey = source.key
                videos.append(video)
            } catch {
                Logger.shared.log("解码第 \(index) 个视频条目失败: \(error)", level: .error)
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        Logger.shared.log("  缺失字段: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .typeMismatch(let type, let context):
                        Logger.shared.log("  类型不匹配: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .valueNotFound(let type, let context):
                        Logger.shared.log("  值为空: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .dataCorrupted(let context):
                        Logger.shared.log("  数据损坏: \(context.debugDescription)", level: .error)
                    @unknown default:
                        Logger.shared.log("  未知解码错误", level: .error)
                    }
                }
                Logger.shared.log("  原始数据: \(item)", level: .debug)
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
        
        do {
            let itemData = try JSONSerialization.data(withJSONObject: first)
            let decoder = JSONDecoder()
            var video = try decoder.decode(Movie.Video.self, from: itemData)
            video.sourceKey = source.key
            
            let playFrom = first["vod_play_from"] as? String ?? ""
            let playUrl = first["vod_play_url"] as? String ?? ""
            
            Logger.shared.log("详情解析成功", level: .info)
            return VodInfo.from(video: video, playFrom: playFrom, playUrl: playUrl)
        } catch {
            Logger.shared.log("解码详情视频失败: \(error)", level: .error)
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    Logger.shared.log("  缺失字段: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                case .typeMismatch(let type, let context):
                    Logger.shared.log("  类型不匹配: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                case .valueNotFound(let type, let context):
                    Logger.shared.log("  值为空: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                case .dataCorrupted(let context):
                    Logger.shared.log("  数据损坏: \(context.debugDescription)", level: .error)
                @unknown default:
                    Logger.shared.log("  未知解码错误", level: .error)
                }
            }
            Logger.shared.log("  原始数据: \(first)", level: .debug)
            throw SourceError.parseError("详情数据解码失败")
        }
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
        for (index, item) in list.enumerated() {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: item)
                let decoder = JSONDecoder()
                var video = try decoder.decode(Movie.Video.self, from: itemData)
                video.sourceKey = source.key
                videos.append(video)
            } catch {
                Logger.shared.log("解码第 \(index) 个视频条目失败: \(error)", level: .error)
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        Logger.shared.log("  缺失字段: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .typeMismatch(let type, let context):
                        Logger.shared.log("  类型不匹配: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .valueNotFound(let type, let context):
                        Logger.shared.log("  值为空: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue })", level: .error)
                    case .dataCorrupted(let context):
                        Logger.shared.log("  数据损坏: \(context.debugDescription)", level: .error)
                    @unknown default:
                        Logger.shared.log("  未知解码错误", level: .error)
                    }
                }
                Logger.shared.log("  原始数据: \(item)", level: .debug)
            }
        }
        
        Logger.shared.log("搜索到 \(videos.count) 个结果", level: .info)
        return videos
    }
}
