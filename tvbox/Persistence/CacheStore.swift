import Foundation

private func makeVodBusinessKey(vodId: String, sourceKey: String) -> String {
    let normalizedVodId = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(normalizedSourceKey)::\(normalizedVodId)"
}

struct VodPlaybackState: Codable {
    var flag: String
    var episodeIndex: Int
    var progressSeconds: Double
}

struct VodCollect: Codable, Identifiable {
    var id: String { bizKey }
    var bizKey: String = ""
    var vodId: String = ""
    var vodName: String = ""
    var vodPic: String = ""
    var sourceKey: String = ""
    var updateTime: Date = Date()

    init(vodId: String, vodName: String, vodPic: String, sourceKey: String) {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.updateTime = Date()
    }
}

struct VodRecord: Codable, Identifiable {
    var id: String { bizKey }
    var bizKey: String = ""
    var vodId: String = ""
    var vodName: String = ""
    var vodPic: String = ""
    var sourceKey: String = ""
    var playNote: String = ""
    var dataJson: String = ""
    var updateTime: Date = Date()

    init(vodId: String, vodName: String, vodPic: String, sourceKey: String, playNote: String = "") {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.playNote = playNote
        self.updateTime = Date()
    }
}

struct CacheItem: Codable {
    var key: String = ""
    var value: String = ""
    var updateTime: Date = Date()

    init(key: String, value: String) {
        self.key = key
        self.value = value
        self.updateTime = Date()
    }
}

@MainActor
class CacheStore: ObservableObject {
    static let shared = CacheStore()

    @Published private(set) var favorites: [VodCollect] = []
    @Published private(set) var records: [VodRecord] = []

    private let fileManager = FileManager.default
    private let collectsFileName = "vod_collects.json"
    private let recordsFileName = "vod_records.json"
    private let cacheItemsFileName = "cache_items.json"

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        favorites = loadJSON(from: collectsFileName)
        records = loadJSON(from: recordsFileName)
    }

    func addCollect(_ video: Movie.Video) {
        let vodId = video.id
        let sourceKey = video.sourceKey
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)

        var items = favorites
        let matched = items.indices.filter { items[$0].bizKey == bizKey || (items[$0].bizKey.isEmpty && items[$0].vodId == vodId && items[$0].sourceKey == sourceKey) }

        if let firstIndex = matched.first {
            items[firstIndex].bizKey = bizKey
            items[firstIndex].vodName = video.name
            items[firstIndex].vodPic = video.pic
            items[firstIndex].updateTime = Date()
            for index in matched.dropFirst().reversed() {
                items.remove(at: index)
            }
        } else {
            let collect = VodCollect(
                vodId: vodId,
                vodName: video.name,
                vodPic: video.pic,
                sourceKey: sourceKey
            )
            items.insert(collect, at: 0)
        }

        favorites = items
        saveJSON(items, to: collectsFileName)
    }

    func removeCollect(vodId: String, sourceKey: String) {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        favorites.removeAll { $0.bizKey == bizKey || ($0.bizKey.isEmpty && $0.vodId == vodId && $0.sourceKey == sourceKey) }
        saveJSON(favorites, to: collectsFileName)
    }

    func isCollected(vodId: String, sourceKey: String) -> Bool {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        return favorites.contains { $0.bizKey == bizKey || ($0.bizKey.isEmpty && $0.vodId == vodId && $0.sourceKey == sourceKey) }
    }

    func addRecord(
        _ video: Movie.Video,
        playNote: String,
        playbackState: VodPlaybackState? = nil
    ) {
        let vodId = video.id
        let sourceKey = video.sourceKey
        let encodedState = Self.encodePlaybackState(playbackState)
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)

        var items = records
        let matched = items.indices.filter { items[$0].bizKey == bizKey || (items[$0].bizKey.isEmpty && items[$0].vodId == vodId && items[$0].sourceKey == sourceKey) }

        if let firstIndex = matched.first {
            items[firstIndex].bizKey = bizKey
            items[firstIndex].playNote = playNote
            if let encodedState {
                items[firstIndex].dataJson = encodedState
            }
            items[firstIndex].updateTime = Date()
            for index in matched.dropFirst().reversed() {
                items.remove(at: index)
            }
        } else {
            var record = VodRecord(
                vodId: vodId,
                vodName: video.name,
                vodPic: video.pic,
                sourceKey: sourceKey,
                playNote: playNote
            )
            if let encodedState {
                record.dataJson = encodedState
            }
            items.insert(record, at: 0)
        }

        records = items
        saveJSON(items, to: recordsFileName)
    }

    func getPlaybackState(vodId: String, sourceKey: String) -> VodPlaybackState? {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        guard let record = records.first(where: { $0.bizKey == bizKey || ($0.bizKey.isEmpty && $0.vodId == vodId && $0.sourceKey == sourceKey) }) else {
            return nil
        }
        return Self.decodePlaybackState(record.dataJson)
    }

    func clearHistory() {
        records = []
        saveJSON(records, to: recordsFileName)
    }

    func removeRecord(vodId: String, sourceKey: String) {
        let bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        records.removeAll { $0.bizKey == bizKey || ($0.bizKey.isEmpty && $0.vodId == vodId && $0.sourceKey == sourceKey) }
        saveJSON(records, to: recordsFileName)
    }

    func setCacheItem(key: String, value: String) {
        var items = loadCacheItems()
        if let index = items.firstIndex(where: { $0.key == key }) {
            items[index].value = value
            items[index].updateTime = Date()
        } else {
            items.append(CacheItem(key: key, value: value))
        }
        saveJSON(items, to: cacheItemsFileName)
    }

    func getCacheItem(key: String) -> String? {
        let items = loadCacheItems()
        return items.first(where: { $0.key == key })?.value
    }

    func removeCacheItem(key: String) {
        var items = loadCacheItems()
        items.removeAll { $0.key == key }
        saveJSON(items, to: cacheItemsFileName)
    }

    private func loadJSON<T: Decodable>(from fileName: String) -> [T] {
        let url = documentsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func saveJSON<T: Encodable>(_ items: [T], to fileName: String) {
        let url = documentsDirectory.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadCacheItems() -> [CacheItem] {
        let url = documentsDirectory.appendingPathComponent(cacheItemsFileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CacheItem].self, from: data)) ?? []
    }

    private static func encodePlaybackState(_ state: VodPlaybackState?) -> String? {
        guard let state else { return nil }
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodePlaybackState(_ json: String) -> VodPlaybackState? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VodPlaybackState.self, from: data)
    }
}
