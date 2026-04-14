import SwiftUI

struct AddNodeSourceView: View {
    @State private var sourceUrl: String = ""
    @State private var sourceName: String = ""
    @State private var isLoading = false
    @State private var showToast = false
    @State private var toastMessage = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            SectionCard(title: "添加远程 Node 源") {
                VStack(spacing: 0) {
                    TextField("源名称", text: $sourceName)
                        .padding(12)
                    
                    Divider()
                    
                    TextEditor(text: $sourceUrl)
                        .placeholder(when: sourceUrl.isEmpty) {
                            Text("请输入源地址\n支持: HTTP地址 / Gitee私有仓库 / GitHub私有仓库")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(minHeight: 100)
                        .padding(12)
                }
            }
            
            Section {
                Button {
                    addSource()
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("添加源")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .background(Color.tint)
                            .cornerRadius(12)
                    }
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("添加 Node 源")
        .navigationBarTitleDisplayMode(.inline)
        .toast(isPresented: $showToast, message: toastMessage)
    }
    
    private func addSource() {
        guard sourceName.isNotEmpty() else {
            toastMessage = "请输入源名称"
            showToast = true
            return
        }
        
        guard sourceUrl.isNotEmpty() else {
            toastMessage = "请输入源地址"
            showToast = true
            return
        }
        
        guard let parsed = SourceUrlParser.parse(sourceUrl) else {
            toastMessage = "源地址格式错误"
            showToast = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let localPath = try await SourceService.shared.downloadRemoteSource(
                    url: parsed.url,
                    sourceName: sourceName,
                    type: parsed.type
                )
                
                let source = SourceBean(
                    name: sourceName,
                    api: sourceUrl,
                    type: 5,
                    localPath: localPath
                )
                
                SourceService.shared.addRemoteSource(source)
                
                await MainActor.run {
                    isLoading = false
                    toastMessage = "源添加成功"
                    showToast = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    toastMessage = "添加失败: \(error.localizedDescription)"
                    showToast = true
                }
            }
        }
    }
}
