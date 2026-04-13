import SwiftUI

struct AddNodeSourceView: View {
    @Environment(\.dismiss) var dismiss
    @State private var sourceUrl = ""
    @State private var sourceName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("源名称", text: $sourceName)
                        .placeholder(when: sourceName.isEmpty) {
                            Text("请输入源名称")
                        }
                    
                    TextField("源地址", text: $sourceUrl)
                        .placeholder(when: sourceUrl.isEmpty) {
                            Text("支持HTTP地址、Gitee/GitHub私有地址")
                        }
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                } header: {
                    Text("远程Node源")
                } footer: {
                    Text("例如：https://xxx.com/source.zip 或者 gitee://token@gitee.com/user/repo/branch/path")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await addSource()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("添加源")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || sourceUrl.isEmpty || sourceName.isEmpty)
                }
            }
            .navigationTitle("添加Node源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addSource() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 解析地址
            guard let (url, type) = SourceService.shared.parseNodeSourceUrl(sourceUrl) else {
                errorMessage = "无效的源地址格式"
                isLoading = false
                return
            }
            
            // 下载源
            let localPath = try await SourceService.shared.downloadRemoteNodeSource(url: url, sourceName: sourceName)
            
            // 保存源
            let newSource = SourceBean(
                id: UUID().uuidString,
                name: sourceName,
                url: sourceUrl,
                localPath: localPath,
                type: type
            )
            
            SourceService.shared.saveSource(newSource)
            
            // 加载源
            NodeJSBridge.shared.loadRemoteSource(path: localPath)
            
            dismiss()
        } catch {
            errorMessage = "添加失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
