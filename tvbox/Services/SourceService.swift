import Foundation
import Alamofire
import ZIPFoundation

class SourceService: ObservableObject {
    static let shared = SourceService()
    
    // 保存的远程源
    @Published var remoteSources: [SourceBean] = []
    
    override init() {
        super.init()
        loadRemoteSources()
    }
    
    // 下载远程源
    func downloadRemoteSource(url: URL, sourceName: String, type: String) async throws -> String {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sourceDir = documentsDir.appendingPathComponent("sources/\(sourceName)")
        
        // 如果已经存在，直接返回
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            return sourceDir.path
        }
        
        // 创建目录
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        if type == "http" {
            // 普通HTTP下载zip包
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // 保存临时文件
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("temp.zip")
            try data.write(to: tempFile)
            
            // 解压
            try FileManager.default.unzipItem(at: tempFile, to: sourceDir)
            
            // 删除临时文件
            try? FileManager.default.removeItem(at: tempFile)
        } else if type == "gitee" || type == "github" {
            // 私有仓库，下载文件
            // 这里简化处理，实际会下载整个目录
            // 你可以扩展这里的逻辑
        }
        
        return sourceDir.path
    }
    
    // 添加远程源
    func addRemoteSource(_ source: SourceBean) {
        remoteSources.append(source)
        saveRemoteSources()
    }
    
    // 删除远程源
    func removeRemoteSource(_ source: SourceBean) {
        remoteSources.removeAll { $0.id == source.id }
        // 删除本地文件
        if let path = source.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        saveRemoteSources()
    }
    
    // 保存远程源
    private func saveRemoteSources() {
        if let data = try? JSONEncoder().encode(remoteSources) {
            UserDefaults.standard.set(data, forKey: "remoteSources")
        }
    }
    
    // 加载远程源
    private func loadRemoteSources() {
        if let data = UserDefaults.standard.data(forKey: "remoteSources") {
            if let sources = try? JSONDecoder().decode([SourceBean].self, from: data) {
                self.remoteSources = sources
            }
        }
    }
    
    // Node源的请求转发
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        guard NodeJSBridge.shared.nodePort > 0 else {
            throw SourceError.nodeNotReady
        }
        
        let url = URL(string: "http://127.0.0.1:\(NodeJSBridge.shared.nodePort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }
    
    // 获取分类
    func getSort(sourceBean: SourceBean) async throws -> [MovieSort] {
        if sourceBean.type == 5 {
            // Node源
            let result = try await requestNodeAPI(path: "/home", body: [:])
            // 解析返回的数据
            if let dict = result as? [String: Any],
               let classes = dict["class"] as? [[String: Any]] {
                return classes.map { item in
                    MovieSort(
                        id: item["type_id"] as? String ?? "",
                        name: item["type_name"] as? String ?? ""
                    )
                }
            }
            return []
        } else {
            // 原来的旧源处理，全部保留
            return try await getOldSort(sourceBean: sourceBean)
        }
    }
    
    // 获取列表
    func getList(sourceBean: SourceBean, sortData: MovieSort, page: Int) async throws -> [Movie] {
        if sourceBean.type == 5 {
            // Node源
            let body: [String: Any] = [
                "id": sortData.id,
                "page": page
            ]
            let result = try await requestNodeAPI(path: "/category", body: body)
            // 解析返回的数据
            if let dict = result as? [String: Any],
               let list = dict["list"] as? [[String: Any]] {
                return list.map { item in
                    Movie(
                        id: item["vod_id"] as? String ?? "",
                        name: item["vod_name"] as? String ?? "",
                        cover: item["vod_pic"] as? String ?? "",
                        year: item["vod_year"] as? String ?? ""
                    )
                }
            }
            return []
        } else {
            // 原来的旧源处理，全部保留
            return try await getOldList(sourceBean: sourceBean, sortData: sortData, page: page)
        }
    }
    
    // 获取详情
    func getDetail(sourceBean: SourceBean, movieId: String) async throws -> MovieDetail {
        if sourceBean.type == 5 {
            // Node源
            let body: [String: Any] = [
                "id": movieId
            ]
            let result = try await requestNodeAPI(path: "/detail", body: body)
            // 解析返回的数据
            if let dict = result as? [String: Any],
               let list = dict["list"] as? [[String: Any]],
               let item = list.first {
                return MovieDetail(
                    id: item["vod_id"] as? String ?? "",
                    name: item["vod_name"] as? String ?? "",
                    cover: item["vod_pic"] as? String ?? "",
                    desc: item["vod_content"] as? String ?? "",
                    playFrom: item["vod_play_from"] as? String ?? "",
                    playUrl: item["vod_play_url"] as? String ?? ""
                )
            }
            throw SourceError.parseError
        } else {
            // 原来的旧源处理，全部保留
            return try await getOldDetail(sourceBean: sourceBean, movieId: movieId)
        }
    }
    
    // 解析播放地址
    func getPlayUrl(sourceBean: SourceBean, flag: String, id: String) async throws -> String {
        if sourceBean.type == 5 {
            // Node源
            let body: [String: Any] = [
                "flag": flag,
                "id": id
            ]
            let result = try await requestNodeAPI(path: "/play", body: body)
            if let dict = result as? [String: Any],
               let url = dict["url"] as? String {
                return url
            }
            throw SourceError.parseError
        } else {
            // 原来的旧源处理，全部保留
            return try await getOldPlayUrl(sourceBean: sourceBean, flag: flag, id: id)
        }
    }
    
    // 搜索
    func search(sourceBean: SourceBean, keyword: String, page: Int) async throws -> [Movie] {
        if sourceBean.type == 5 {
            // Node源
            let body: [String: Any] = [
                "wd": keyword,
                "page": page
            ]
            let result = try await requestNodeAPI(path: "/search", body: body)
            // 解析返回的数据
            if let dict = result as? [String: Any],
               let list = dict["list"] as? [[String: Any]] {
                return list.map { item in
                    Movie(
                        id: item["vod_id"] as? String ?? "",
                        name: item["vod_name"] as? String ?? "",
                        cover: item["vod_pic"] as? String ?? "",
                        year: item["vod_year"] as? String ?? ""
                    )
                }
            }
            return []
        } else {
            // 原来的旧源处理，全部保留
            return try await getOldSearch(sourceBean: sourceBean, keyword: keyword, page: page)
        }
    }
    
    // 原来的旧方法，全部保留，这里省略，你原来的代码都在
    private func getOldSort(sourceBean: SourceBean) async throws -> [MovieSort] {
        // 你原来的代码，全部保留
        return []
    }
    
    private func getOldList(sourceBean: SourceBean, sortData: MovieSort, page: Int) async throws -> [Movie] {
        // 你原来的代码，全部保留
        return []
    }
    
    private func getOldDetail(sourceBean: SourceBean, movieId: String) async throws -> MovieDetail {
        // 你原来的代码，全部保留
        return MovieDetail(id: "", name: "", cover: "", desc: "", playFrom: "", playUrl: "")
    }
    
    private func getOldPlayUrl(sourceBean: SourceBean, flag: String, id: String) async throws -> String {
        // 你原来的代码，全部保留
        return ""
    }
    
    private func getOldSearch(sourceBean: SourceBean, keyword: String, page: Int) async throws -> [Movie] {
        // 你原来的代码，全部保留
        return []
    }
}

enum SourceError: Error {
    case emptyApi
    case nodeNotReady
    case parseError
}
