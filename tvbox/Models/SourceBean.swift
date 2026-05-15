import Foundation

/// 视频源站点配置 - 对应 Android 版 SourceBean.java
struct SourceBean: Codable, Identifiable, Hashable {
    /// 以源 key 作为稳定标识。
    var id: String { key }
    
    /// 源唯一键。
    let key: String
    /// 源显示名。
    let name: String
    /// 源接口地址。
    let api: String
    /// 搜索开关：0 关闭，1 开启。
    let searchable: Int
    /// 是否允许出现在首页分类：0 不可选，1 可选。
    let filterable: Int
    /// 快速搜索开关：0 关闭，1 开启（主要用于 remote 源 quick 参数）。
    let quickSearch: Int
    /// 源声明的播放器类型（历史字段，Swift 端目前主要走统一播放器策略）。
    let playerType: Int
    /// 源协议类型：0 XML，1 JSON，3 JAR，4 Remote。
    let type: Int
    /// 扩展参数（remote 源常用）。
    let ext: String?
    /// 索引标记：1 表示索引服务（如豆瓣），点击视频应跳转搜索。
    let indexs: Int
    
    init(key: String = "", name: String = "", api: String = "",
         searchable: Int = 1, filterable: Int = 1, quickSearch: Int = 0,
         playerType: Int = 0, type: Int = 1, ext: String? = nil,
         indexs: Int = 0) {
        self.key = key
        self.name = name
        self.api = api
        self.searchable = searchable
        self.filterable = filterable
        self.quickSearch = quickSearch
        self.playerType = playerType
        self.type = type
        self.ext = ext
        self.indexs = indexs
    }
    
    var isSearchable: Bool { searchable == 1 }
    var isFilterable: Bool { filterable == 1 }
    var isQuickSearchEnabled: Bool { quickSearch == 1 }
    
    var isSupportedInSwift: Bool {
        return type == 0 || type == 1 || type == 3 || type == 4
    }
    
    var isSpiderSource: Bool {
        return type == 3
    }
    
    var isIndexSite: Bool {
        return indexs == 1 || key == "douban"
    }
    
    var isConfigCenter: Bool {
        return key == "baseset"
    }
    
    /// 类型描述
    var typeDescription: String {
        switch type {
        case 0: return "XML"
        case 1: return "JSON"
        case 3: return "Spider"
        case 4: return "Remote"
        default: return "未知"
        }
    }
    
    /// api 字段是否为有效 HTTP URL
    var isHttpApi: Bool {
        return api.hasPrefix("http://") || api.hasPrefix("https://")
    }
}
