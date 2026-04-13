import SwiftUI

struct AddNodeSourceView: View {
    @State private var sourceUrl = ""
    @State private var sourceName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("源名称", text: $sourceName)
                TextField("源地址", text: $sourceUrl)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            Section {
                Button("添加源") {
                    Task {
                        await addSource()
                    }
                }
                .disabled(isLoading || sourceName.isEmpty || sourceUrl.isEmpty)
            }
        }
        .navigationTitle("添加Node源")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("正在下载源...")
            }
        }
    }
    
    private func addSource() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 解析地址
            guard let (url, type) = SourceService.shared.parseNodeSourceUrl(sourceUrl) else {
                errorMessage = "无效的源地址"
                isLoading = false
                return
            }
            
            // 下载源
            let localPath = try await SourceService.shared.downloadRemoteNodeSource(url: url, sourceName: sourceName)
            
            // 创建源Bean
            let newSource = SourceBean(
                id: UUID().uuidString,
                name: sourceName,
                key: "node_\(sourceName)",
                type: 3,
                api: "node://\(sourceName)",
                search: 1,
                group: "Node源",
                localPath: localPath,
                sourceType: type
            )
            
            // 保存源
            SourceService.shared.saveSource(newSource)
            
            // 加载源
            NodeJSBridge.shared.loadRemoteSource(path: localPath)
            
            dismiss()
        } catch {
            errorMessage = "下载失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
