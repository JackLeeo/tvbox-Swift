import SwiftUI
import ZIPFoundation

struct AddNodeSourceView: View {
    @State private var sourceUrl = ""
    @State private var sourceName = ""
    @State private var isLoading = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var existingSources: [RemoteSource] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SectionCard(title: "添加远程 Node 源") {
                        VStack(spacing: 12) {
                            TextField("源名称", text: $sourceName)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: sourceName.isEmpty) {
                                    Text("请输入源名称")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            
                            TextEditor(text: $sourceUrl)
                                .frame(minHeight: 100)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: sourceUrl.isEmpty) {
                                    Text("请输入源地址\n支持：\n- 普通 HTTP/HTTPS 地址\n- Gitee 私有仓库: gitee://token@gitee.com/user/repo/branch/path\n- GitHub 私有仓库: github://token@github.com/user/repo/branch/path")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    Button {
                        Task {
                            await addSource()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        } else {
                            Text("添加源")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(isLoading)
                    
                    // 已添加的源列表
                    if !existingSources.isEmpty {
                        SectionCard(title: "已添加的源") {
                            VStack(spacing: 0) {
                                ForEach(existingSources, id: \.name) { source in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(source.name)
                                                .font(.headline)
                                            Text(source.url)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            loadSource(source)
                                        } label: {
                                            Text("加载")
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.green)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                        
                                        Button {
                                            deleteSource(source)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    
                                    if source.name != existingSources.last?.name {
                                        Divider().background(Color.white.opacity(0.1))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(AppTheme.primaryGradient.ignoresSafeArea())
            .navigationTitle("添加 Node 源")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toast(isPresented: $showToast, message: toastMessage)
            .onAppear {
                existingSources = SourceService.shared.getRemoteSources()
            }
        }
    }
    
    private func addSource() async {
        guard !sourceName.isEmpty, !sourceUrl.isEmpty else {
            toastMessage = "请填写完整信息"
            showToast = true
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // 解析源地址
        guard let (url, type) = SourceService.shared.parseNodeSourceUrl(sourceUrl) else {
            toastMessage = "无效的源地址格式"
            showToast = true
            return
        }
        
        do {
            // 下载源文件
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // 获取 Documents 目录
            let documentsDir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let sourceDir = documentsDir.appendingPathComponent("node_sources/\(sourceName)")
            
            // 如果目录已存在，先删除
            if FileManager.default.fileExists(atPath: sourceDir.path) {
                try FileManager.default.removeItem(at: sourceDir)
            }
            
            // 创建目录
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            
            // 如果是 zip 文件，解压
            if url.pathExtension == "zip" {
                let tempZip = try FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                try data.write(to: tempZip)
                try FileManager.default.unzipItem(at: tempZip, to: sourceDir)
                try FileManager.default.removeItem(at: tempZip)
            } else {
                // 普通 js 文件
                let fileURL = sourceDir.appendingPathComponent("index.js")
                try data.write(to: fileURL)
            }
            
            // 保存源信息
            try await SourceService.shared.saveRemoteSource(
                name: sourceName,
                url: sourceUrl,
                localPath: sourceDir.path
            )
            
            // 加载这个源
            NodeJSBridge.shared.loadRemoteSource(path: sourceDir.path)
            
            // 刷新列表
            existingSources = SourceService.shared.getRemoteSources()
            
            // 清空输入
            sourceName = ""
            sourceUrl = ""
            
            toastMessage = "源添加成功并已加载"
            showToast = true
        } catch {
            toastMessage = "添加失败: \(error.localizedDescription)"
            showToast = true
        }
    }
    
    private func loadSource(_ source: RemoteSource) {
        NodeJSBridge.shared.loadRemoteSource(path: source.localPath)
        toastMessage = "已加载源: \(source.name)"
        showToast = true
    }
    
    private func deleteSource(_ source: RemoteSource) {
        // 删除本地文件
        do {
            try FileManager.default.removeItem(atPath: source.localPath)
        } catch {
            Logger.shared.log("删除源文件失败: \(error)", level: .error)
        }
        
        // 从保存的列表中删除
        var sources = SourceService.shared.getRemoteSources()
        sources.removeAll { $0.name == source.name }
        
        // 保存
        do {
            let data = try JSONEncoder().encode(sources)
            UserDefaults.standard.set(data, forKey: "RemoteSources")
        } catch {
            Logger.shared.log("保存源列表失败: \(error)", level: .error)
        }
        
        // 刷新列表
        existingSources = sources
        
        toastMessage = "已删除源: \(source.name)"
        showToast = true
    }
}

// Placeholder 扩展
extension View {
    func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// Toast 扩展
struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                VStack {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.top, 60)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String) -> some View {
        self.modifier(ToastModifier(isPresented: isPresented, message: message))
    }
}
