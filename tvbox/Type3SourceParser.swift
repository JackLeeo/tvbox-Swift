import Foundation

class Type3SourceParser {
    static let shared = Type3SourceParser()
    private let nodeBridge = NodeJSBridge.shared
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers, completion: completion)
    }
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        try await nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers)
    }
}
