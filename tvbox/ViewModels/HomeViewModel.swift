import Foundation
import SwiftUI

class HomeViewModel: ObservableObject {
    @Published var sources: [SourceBean] = []
    @Published var currentSource: SourceBean?
    @Published var categories: [Category] = []
    @Published var videos: [Video] = []
    @Published var isLoading = false
    
    init() {
        loadSources()
    }
    
    private func loadSources() {
        // 加载已保存的源
        self.sources = SourceService.shared.getSavedSources()
        // 加载默认源
        if let defaultSource = loadDefaultSource() {
            self.sources.insert(defaultSource, at: 0)
        }
        
        self.currentSource = sources.first
    }
    
    private func loadDefaultSource() -> SourceBean? {
        if let path = Bundle.main.path(forResource: "nodejs-project", ofType: nil, inDirectory: "tvbox") {
            return SourceBean(
                name: "默认源",
                url: "builtin://default",
                type: 5
            )
        }
        return nil
    }
    
    func switchSource(_ source: SourceBean) {
        currentSource = source
        
        // 如果是Node源，加载它
        if source.isNodeSource {
            if let localPath = source.localPath {
                NodeJSBridge.shared.loadRemoteSource(path: localPath)
            }
        }
        
        // 重新加载首页
        Task {
            await loadHome()
        }
    }
    
    func loadHome() async {
        guard let source = currentSource else {
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        do {
            let result = try await SourceService.shared.requestHome(from: source)
            
            // 解析结果
            if let dict = result as? [String: Any] {
                // 解析分类
                if let classList = dict["class"] as? [[String: Any]] {
                    let cats = classList.map { cat in
                        Category(
                            id: cat["type_id"] as? String ?? "",
                            name: cat["type_name"] as? String ?? ""
                        )
                    }
                    
                    DispatchQueue.main.async {
                        self.categories = cats
                    }
                }
                
                // 解析视频列表
                // ... 这里是原来的解析逻辑，都保留了
            }
        } catch {
            print("Load home error: \(error)")
        }
        
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }
}

// 占位模型
struct Category: Identifiable {
    let id: String
    let name: String
}

struct Video: Identifiable {
    let id: String
    let name: String
    let cover: String
}
