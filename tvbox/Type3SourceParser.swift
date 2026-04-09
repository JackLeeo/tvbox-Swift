import Foundation

class Type3SourceParser {
    static let shared = Type3SourceParser()
    private let nodeBridge = NodeJSBridge.shared
    
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        nodeBridge.parseType3Source(sourceUrl: sourceUrl, headers: headers, completion: completion)
    }
    
    /// async/await 异步版本，方便SwiftUI调用
    func parseType3Source(sourceUrl: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            parseType3Source(sourceUrl: sourceUrl, headers: headers) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "Type3Parser", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析失败"]))
                }
            }
        }
    }
}
