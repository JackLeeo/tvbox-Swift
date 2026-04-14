import Foundation
import Alamofire
import ZIPFoundation

class SourceService {
    static let shared = SourceService()
    
    private var currentSource: SourceBean?
    private var savedSources: [SourceBean] = []
    
    private init() {
        loadSavedSources()
    }
    
    // MARK: - 源管理
    private func loadSavedSources() {
        if let data = UserDefaults.standard.data(forKey: "SavedSources") {
            if let sources = try? JSONDecoder().decode([SourceBean].self, from: data) {
                self.savedSources = sources
            }
        }
    }
    
    private func saveSavedSources() {
        if let data = try? JSONEncoder().encode(savedSources) {
            UserDefaults.standard.set(data, forKey: "SavedSources")
        }
    }
    
    func getSavedSources() -> [SourceBean] {
        return savedSources
    }
    
    func addSource(_ source: SourceBean) {
        savedSources.append(source)
        saveSavedSources()
    }
    
    func removeSource(_ source: SourceBean) {
        savedSources.removeAll { $0.id == source.id }
        saveSavedSources()
        
        // 删除本地文件
        if let localPath = source.localPath {
            try? FileManager.default.removeItem(atPath: localPath)
        }
    }
    
    // MARK: - 远程源下载
    func downloadRemoteNodeSource(url: URL, sourceName: String) async throws -> SourceBean {
        // 1. 下载远程的zip包
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // 2. 创建本地目录
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sourceDir = documentsDir.appendingPathComponent("node-sources/\(sourceName)")
        
        // 删除已存在的
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            try FileManager.default.removeItem(at: sourceDir)
        }
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // 3. 解压
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try data.write(to: tempFile)
        
        try FileManager.default.unzipItem(at: tempFile, to: sourceDir)
        
        try? FileManager.default.removeItem(at: tempFile)
        
        // 4. 创建源
        var source = SourceBean(name: sourceName, url: url.absoluteString, type: 5)
        source.localPath = sourceDir.path
        
        addSource(source)
        
        // 5. 加载源
        NodeJSBridge.shared.loadRemoteSource(path: sourceDir.path)
        
        return source
    }
    
    // MARK: - API请求
    func requestNodeAPI(path: String, body: [String: Any]) async throws -> Any {
        return try await NodeJSBridge.shared.requestNodeAPI(path: path, body: body)
    }
    
    func requestHome(from source: SourceBean) async throws -> Any {
        if source.isNodeSource {
            return try await requestNodeAPI(path: "/home", body: [:])
        } else {
            // 旧的源处理逻辑
            return try await Type3SourceParser.shared.parseHome(from: source)
        }
    }
    
    func requestCategory(id: String, page: Int, filters: [String: Any], from source: SourceBean) async throws -> Any {
        if source.isNodeSource {
            return try await requestNodeAPI(path: "/category", body: [
                "id": id,
                "page": page,
                "filters": filters
            ])
        } else {
            // 旧的源处理逻辑
            return try await Type3SourceParser.shared.parseCategory(id: id, page: page, filters: filters, from: source)
        }
    }
    
    func requestDetail(ids: [String], from source: SourceBean) async throws -> Any {
        if source.isNodeSource {
            return try await requestNodeAPI(path: "/detail", body: [
                "id": ids
            ])
        } else {
            // 旧的源处理逻辑
            return try await Type3SourceParser.shared.parseDetail(ids: ids, from: source)
        }
    }
    
    func requestPlay(flag: String, id: String, from source: SourceBean) async throws -> Any {
        if source.isNodeSource {
            return try await requestNodeAPI(path: "/play", body: [
                "flag": flag,
                "id": id
            ])
        } else {
            // 旧的源处理逻辑
            return try await Type3SourceParser.shared.parsePlay(flag: flag, id: id, from: source)
        }
    }
    
    func requestSearch(wd: String, page: Int, from source: SourceBean) async throws -> Any {
        if source.isNodeSource {
            return try await requestNodeAPI(path: "/search", body: [
                "wd": wd,
                "page": page
            ])
        } else {
            // 旧的源处理逻辑
            return try await Type3SourceParser.shared.parseSearch(wd: wd, page: page, from: source)
        }
    }
}

// 占位，旧的解析器
class Type3SourceParser {
    static let shared = Type3SourceParser()
    
    func parseHome(from source: SourceBean) async throws -> Any {
        throw SourceError.emptyApi
    }
    
    func parseCategory(id: String, page: Int, filters: [String: Any], from source: SourceBean) async throws -> Any {
        throw SourceError.emptyApi
    }
    
    func parseDetail(ids: [String], from source: SourceBean) async throws -> Any {
        throw SourceError.emptyApi
    }
    
    func parsePlay(flag: String, id: String, from source: SourceBean) async throws -> Any {
        throw SourceError.emptyApi
    }
    
    func parseSearch(wd: String, page: Int, from source: SourceBean) async throws -> Any {
        throw SourceError.emptyApi
    }
}

enum SourceError: Error {
    case emptyApi
}
