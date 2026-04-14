import SwiftUI

struct AddNodeSourceView: View {
    @State private var sourceName = ""
    @State private var sourceUrl = ""
    @State private var isLoading = false
    @State private var showToast = false
    @State private var toastMessage = ""
    
    @State private var existingSources: [RemoteSource] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("源名称", text: $sourceName)
                    TextField("源地址", text: $sourceUrl)
                }
                
                Section {
                    Button("添加源") {
                        addSource()
                    }
                    .disabled(isLoading)
                }
                
                if !existingSources.isEmpty {
                    Section(header: Text("已添加的源")) {
                        ForEach(existingSources) { source in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(source.name)
                                        .font(.body)
                                    Text(source.url)
                                        .font(.caption)
                                        .foregroundColor(.secondaryLabel)
                                }
                                
                                Spacer()
                                
                                Button("加载") {
                                    loadSource(source)
                                }
                                .buttonStyle(.bordered)
                                
                                Button("删除") {
                                    deleteSource(source)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加 Node 源")
            .navigationBarTitleDisplayMode(.large)
            .toast(isPresented: $showToast, message: toastMessage)
            .background(Color.background)
            .onAppear {
                existingSources = SourceService.shared.getRemoteSources()
            }
        }
    }
    
    private func addSource() {
        guard !sourceName.isEmpty, !sourceUrl.isEmpty else {
            toastMessage = "请填写完整信息"
            showToast = true
            return
        }
        
        guard let url = SourceService.shared.parseNodeSourceUrl(sourceUrl) else {
            toastMessage = "源地址格式错误"
            showToast = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let localPath = try await SourceService.shared.downloadRemoteNodeSource(url: url, sourceName: sourceName)
                
                let source = RemoteSource(name: sourceName, url: sourceUrl, localPath: localPath)
                SourceService.shared.saveRemoteSource(source)
                
                // 加载源
                NodeJSBridge.shared.loadRemoteSource(path: localPath)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.toastMessage = "源已添加并加载"
                    self.showToast = true
                    self.existingSources = SourceService.shared.getRemoteSources()
                    self.sourceName = ""
                    self.sourceUrl = ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.toastMessage = "添加失败: \(error.localizedDescription)"
                    self.showToast = true
                }
            }
        }
    }
    
    private func loadSource(_ source: RemoteSource) {
        NodeJSBridge.shared.loadRemoteSource(path: source.localPath)
        toastMessage = "已加载源: \(source.name)"
        showToast = true
    }
    
    private func deleteSource(_ source: RemoteSource) {
        SourceService.shared.removeSource(source)
        try? FileManager.default.removeItem(atPath: source.localPath)
        existingSources = SourceService.shared.getRemoteSources()
        toastMessage = "已删除源: \(source.name)"
        showToast = true
    }
}
