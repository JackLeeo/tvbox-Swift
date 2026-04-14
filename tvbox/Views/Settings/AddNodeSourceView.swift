import SwiftUI

struct AddNodeSourceView: View {
    @State private var sourceUrl = ""
    @State private var sourceName = ""
    @State private var isDownloading = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionCard(title: "添加远程 Node 源") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "link",
                            title: "源地址",
                            placeholder: "输入远程源地址，支持 http/gitee/github",
                            text: $sourceUrl
                        )
                        
                        Divider()
                        
                        TextFieldRow(
                            icon: "tag",
                            title: "源名称",
                            placeholder: "给你的源起个名字",
                            text: $sourceName
                        )
                    }
                }
                
                // 已添加的源列表
                if !SourceService.shared.getSavedSources().isEmpty {
                    SectionCard(title: "已添加的源") {
                        VStack(spacing: 0) {
                            ForEach(SourceService.shared.getSavedSources()) { source in
                                SourceRow(source: source)
                            }
                        }
                    }
                }
                
                // 添加按钮
                Button(action: addSource) {
                    if isDownloading {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("下载中...")
                                .font(.headline)
                        }
                    } else {
                        Text("添加源")
                            .font(.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.tint)
                .cornerRadius(12)
                .disabled(isDownloading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("添加 Node 源")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.background)
        .toast(isPresented: $showToast, message: toastMessage)
    }
    
    private func addSource() {
        guard !sourceUrl.trimmingWhitespace().isEmpty else {
            toastMessage = "请输入源地址"
            showToast = true
            return
        }
        
        guard !sourceName.trimmingWhitespace().isEmpty else {
            toastMessage = "请输入源名称"
            showToast = true
            return
        }
        
        let trimmedUrl = sourceUrl.trimmingWhitespace()
        let trimmedName = sourceName.trimmingWhitespace()
        
        // 解析地址
        let dummySource = SourceBean(name: trimmedName, url: trimmedUrl, type: 5)
        guard let (url, type) = dummySource.parseNodeSourceUrl() else {
            toastMessage = "源地址格式不正确"
            showToast = true
            return
        }
        
        isDownloading = true
        
        Task {
            do {
                _ = try await SourceService.shared.downloadRemoteNodeSource(url: url, sourceName: trimmedName)
                
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.toastMessage = "源添加成功"
                    self.showToast = true
                    self.sourceUrl = ""
                    self.sourceName = ""
                    
                    // 延迟关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.toastMessage = "下载失败: \(error.localizedDescription)"
                    self.showToast = true
                }
            }
        }
    }
}

// MARK: - SourceRow
struct SourceRow: View {
    let source: SourceBean
    @State private var showDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body)
                    .foregroundColor(.label)
                
                Text(source.url)
                    .font(.caption)
                    .foregroundColor(.secondaryLabel)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("加载") {
                    if let localPath = source.localPath {
                        NodeJSBridge.shared.loadRemoteSource(path: localPath)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.tint)
                
                Button("删除") {
                    showDeleteAlert = true
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                SourceService.shared.removeSource(source)
            }
        } message: {
            Text("确定要删除这个源吗？")
        }
    }
}
