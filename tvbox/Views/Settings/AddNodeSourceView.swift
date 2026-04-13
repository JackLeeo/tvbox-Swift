
import SwiftUI

struct AddNodeSourceView: View {
    @State private var sourceUrl: String = ""
    @State private var sourceName: String = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMsg: String?
    
    var body: some View {
        Form {
            Section(header: Text("远程Node源信息")) {
                TextField("源名称", text: $sourceName)
                TextField("源地址", text: $sourceUrl)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                Text("支持普通HTTP地址、Gitee私有仓库地址、GitHub私有仓库地址")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                Button("添加源") {
                    Task {
                        await addSource()
                    }
                }
                .disabled(isLoading)
            }
            if let errorMsg = errorMsg {
                Section {
                    Text(errorMsg)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("添加Node源")
        .alert("添加成功", isPresented: $showSuccess) {
            Button("确定", role: .cancel) {}
        }
    }
    
    private func addSource() async {
        isLoading = true
        errorMsg = nil
        do {
            // 1. 解析地址
            guard let (url, type) = SourceService.shared.parseNodeSourceUrl(sourceUrl) else {
                errorMsg = "无效的源地址"
                isLoading = false
                return
            }
            // 2. 下载源
            let localPath = try await SourceService.shared.downloadRemoteNodeSource(url: url, sourceName: sourceName)
            // 3. 创建源模型
            let source = SourceBean(
                id: UUID().uuidString,
                name: sourceName,
                api: "",
                key: "node_\(sourceName)",
                type: 5, // Node源的type
                ext: nil
            )
            var newSource = source
            newSource.localPath = localPath
            // 4. 保存源
            SourceService.shared.saveSource(newSource)
            // 5. 加载源
            NodeJSBridge.shared.loadRemoteSource(path: localPath)
            
            showSuccess = true
        } catch {
            errorMsg = "添加失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
