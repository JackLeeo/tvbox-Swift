import SwiftUI

struct DiskConfigView: View {
    @State private var config = DiskConfig.load()
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SectionCard(title: "阿里云盘") {
                        VStack(spacing: 12) {
                            TextEditor(text: $config.aliToken)
                                .frame(minHeight: 80)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.aliToken.isEmpty) {
                                    Text("请输入阿里云盘 refresh_token")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    SectionCard(title: "夸克网盘") {
                        VStack(spacing: 12) {
                            TextEditor(text: $config.quarkCookie)
                                .frame(minHeight: 80)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.quarkCookie.isEmpty) {
                                    Text("请输入夸克网盘 Cookie")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    SectionCard(title: "115 网盘") {
                        VStack(spacing: 12) {
                            TextEditor(text: $config.pan115Cookie)
                                .frame(minHeight: 80)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.pan115Cookie.isEmpty) {
                                    Text("请输入 115 网盘 Cookie")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    SectionCard(title: "天翼云盘") {
                        VStack(spacing: 12) {
                            TextEditor(text: $config.tianyiToken)
                                .frame(minHeight: 80)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.tianyiToken.isEmpty) {
                                    Text("请输入天翼云盘 token")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    SectionCard(title: "AList") {
                        VStack(spacing: 12) {
                            TextField("AList 地址", text: $config.alistUrl)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                            
                            TextEditor(text: $config.alistToken)
                                .frame(minHeight: 60)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.alistToken.isEmpty) {
                                    Text("AList Token")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    SectionCard(title: "直播源") {
                        VStack(spacing: 12) {
                            TextEditor(text: $config.liveUrl)
                                .frame(minHeight: 60)
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                                .placeholder(when: config.liveUrl.isEmpty) {
                                    Text("直播源地址")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                        }
                    }
                    
                    Button {
                        saveConfig()
                    } label: {
                        Text("保存配置")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(AppTheme.primaryGradient.ignoresSafeArea())
            .navigationTitle("网盘配置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toast(isPresented: $showToast, message: toastMessage)
        }
    }
    
    private func saveConfig() {
        config.save()
        
        // 如果 Node 已经启动，重新加载源以应用新配置
        if NodeJSBridge.shared.isNodeReady {
            // 重新加载当前源
            if let remoteSources = SourceService.shared.getRemoteSources().last {
                NodeJSBridge.shared.loadRemoteSource(path: remoteSources.localPath)
            } else {
                // 加载默认源
                NodeJSBridge.shared.loadDefaultSource()
            }
        }
        
        toastMessage = "配置已保存"
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
