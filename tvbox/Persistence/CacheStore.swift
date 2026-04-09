import Foundation

// MARK: - 业务键生成工具
private func makeVodBusinessKey(vodId: String, sourceKey: String) -> String {
    let normalizedVodId = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(normalizedSourceKey)::\(normalizedVodId)"
}

// MARK: - 播放续播状态模型
struct VodPlaybackState: Codable {
    var flag: String
    var episodeIndex: Int
    var progressSeconds: Double
}

// MARK: - 收藏数据模型（普通结构体，Codable）
struct VodCollect: Codable, Identifiable, Equatable {
    var id: String { bizKey }
    var bizKey: String
    var vodId: String
    var vodName: String
    var vodPic: String
    var sourceKey: String
    var updateTime: Date
    
    init(vodId: String, vodName: String, vodPic: String, sourceKey: String) {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.updateTime = Date()
    }
}

// MARK: - 历史记录模型（普通结构体，Codable）
struct VodRecord: Codable, Identifiable, Equatable {
    var id: String { bizKey }
    var bizKey: String
    var vodId: String
    var vodName: String
    var vodPic: String
    var sourceKey: String
    var playNote: String
    var dataJson: String
    var updateTime: Date
    
    init(vodId: String, vodName: String, vodPic: String, sourceKey: String, playNote: String = "") {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.playNote = playNote
        self.dataJson = ""
        self.updateTime = Date()
    }
}

// MARK: - 缓存条目模型（普通结构体，Codable）
struct CacheItem: Codable, Identifiable, Equatable {
    var id: String { key }
    var key: String
    var value: String
    var updateTime: Date
    
    init(key: String, value: String) {
        self.key = key
        self.value = value
        self.updateTime = Date()
    }
}

// MARK: - 缓存管理器（使用 UserDefaults 存储）
actor CacheStore {
    static let shared = CacheStore()
    
    private let defaults = UserDefaults.standard
    private let collectsKey = "com.tvbox.cache.collects"
    private let recordsKey = "com.tvbox.cache.records"
    private let cacheItemsKey = "com.tvbox.cache.items"
    
    private init() {}
    
    // MARK: - 私有辅助方法
    
    /// 加载所有收藏
    private func loadCollects() -> [VodCollect] {
        guard let data = defaults.data(forKey: collectsKey),
              let collects = try? JSONDecoder().decode([VodCollect].self, from: data) else {
            return []
        }
        return collects
    }
    
    /// 保存收藏列表
    private func saveCollects(_ collects: [VodCollect]) {
        if let data = try? JSONEncoder().encode(collects) {
            defaults.set(data, forKey: collectsKey)
        }
    }
    
    /// 加载所有历史记录
    private func loadRecords() -> [VodRecord] {
        guard let data = defaults.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([VodRecord].self, from: data) else {
            return []
        }
        return records
    }
    
    /// 保存历史记录列表
    private func saveRecords(_ records: [VodRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
    }
    
    /// 加载所有缓存条目
    private func loadCacheItems() -> [CacheItem] {
        guard let data = defaults.data(forKey: cacheItemsKey),
              let items = try? JSONDecoder().decode([CacheItem].self, from: data) else {
            return []
        }
        return items
    }
    
    /// 保存缓存条目列表
    private func saveCacheItems(_ items: [CacheItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: cacheItemsKey)
        }
    }
    
    /// 编码续播状态为 JSON 字符串
    private static func encodePlaybackState(_ state: VodPlaybackState?) -> String? {
        guard let state else { return nil }
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// 从 JSON 字符串解码续播状态
    private static func decodePlaybackState(_ json: String) -> VodPlaybackState? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VodPlaybackState.self, from: data)
    }
    
    // MARK: - 收藏相关公共方法
    
    /// 添加或更新收藏
    func addCollect(_ video: Movie.Video) {
        let vodId = video.id
        let sourceKey = video.sourceKey
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        
        var collects = loadCollects()
        
        // 找到所有匹配项（包括旧版无 bizKey 的数据）
        let matchedIndices = collects.indices.filter { idx in
            let item = collects[idx]
            return item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }
        
        if let firstIndex = matchedIndices.first {
            // 更新第一个匹配项
            collects[firstIndex].bizKey = bizKey
            collects[firstIndex].vodName = video.name
            collects[firstIndex].vodPic = video.pic
            collects[firstIndex].updateTime = Date()
            
            // 删除其他重复项
            for index in matchedIndices.dropFirst().sorted(by: >) {
                collects.remove(at: index)
            }
        } else {
            // 新建收藏
            let collect = VodCollect(vodId: vodId, vodName: video.name, vodPic: video.pic, sourceKey: sourceKey)
            collects.append(collect)
        }
        
        // 按更新时间降序排列
        collects.sort { $0.updateTime > $1.updateTime }
        saveCollects(collects)
    }
    
    /// 删除收藏
    func removeCollect(vodId: String, sourceKey: String) {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        var collects = loadCollects()
        collects.removeAll { item in
            item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }
        saveCollects(collects)
    }
    
    /// 判断是否已收藏
    func isCollected(vodId: String, sourceKey: String) -> Bool {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        let collects = loadCollects()
        return collects.contains { item in
            item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }
    }
    
    /// 获取所有收藏（按更新时间降序）
    func getAllCollects() -> [VodCollect] {
        loadCollects()
    }
    
    // MARK: - 历史记录相关公共方法
    
    /// 添加或更新播放记录
    func addRecord(
        _ video: Movie.Video,
        playNote: String,
        playbackState: VodPlaybackState? = nil
    ) {
        let vodId = video.id
        let sourceKey = video.sourceKey
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        let encodedState = Self.encodePlaybackState(playbackState)
        
        var records = loadRecords()
        
        let matchedIndices = records.indices.filter { idx in
            let item = records[idx]
            return item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }
        
        if let firstIndex = matchedIndices.first {
            // 更新已有记录
            records[firstIndex].bizKey = bizKey
            records[firstIndex].playNote = playNote
            if let encodedState {
                records[firstIndex].dataJson = encodedState
            }
            records[firstIndex].updateTime = Date()
            
            // 删除重复记录
            for index in matchedIndices.dropFirst().sorted(by: >) {
                records.remove(at: index)
            }
        } else {
            // 新建记录
            var record = VodRecord(vodId: vodId, vodName: video.name, vodPic: video.pic, sourceKey: sourceKey, playNote: playNote)
            if let encodedState {
                record.dataJson = encodedState
            }
            records.append(record)
        }
        
        // 按播放时间降序排列
        records.sort { $0.updateTime > $1.updateTime }
        saveRecords(records)
    }
    
    /// 获取续播状态
    func getPlaybackState(vodId: String, sourceKey: String) -> VodPlaybackState? {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        let records = loadRecords()
        guard let record = records.first(where: { item in
            item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }) else {
            return nil
        }
        return Self.decodePlaybackState(record.dataJson)
    }
    
    /// 获取所有历史记录（按播放时间降序）
    func getAllRecords() -> [VodRecord] {
        loadRecords()
    }
    
    /// 清空所有历史记录
    func clearHistory() {
        defaults.removeObject(forKey: recordsKey)
    }
    
    /// 删除单条历史记录
    func removeRecord(vodId: String, sourceKey: String) {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        var records = loadRecords()
        records.removeAll { item in
            item.bizKey == bizKey || (item.bizKey.isEmpty && item.vodId == vodId && item.sourceKey == sourceKey)
        }
        saveRecords(records)
    }
    
    // MARK: - 通用缓存方法
    
    /// 设置缓存值
    func setCache(key: String, value: String) {
        var items = loadCacheItems()
        if let index = items.firstIndex(where: { $0.key == key }) {
            items[index].value = value
            items[index].updateTime = Date()
        } else {
            items.append(CacheItem(key: key, value: value))
        }
        saveCacheItems(items)
    }
    
    /// 获取缓存值
    func getCache(key: String) -> String? {
        let items = loadCacheItems()
        return items.first(where: { $0.key == key })?.value
    }
    
    /// 删除指定缓存
    func removeCache(key: String) {
        var items = loadCacheItems()
        items.removeAll { $0.key == key }
        saveCacheItems(items)
    }
    
    /// 清空所有缓存
    func clearAllCache() {
        defaults.removeObject(forKey: cacheItemsKey)
    }
}
