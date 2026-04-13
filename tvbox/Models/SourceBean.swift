import Foundation

struct SourceBean: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let key: String
    let type: Int
    let api: String
    let search: Int?
    let group: String?
    
    // 新增的远程源字段
    var localPath: String?
    var sourceType: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, key, type, api, search, group
        case localPath, sourceType
    }
}
